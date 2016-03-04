require Logger

defmodule ChatServer do

	use Application

	def start(_type, _args) do
		import Supervisor.Spec, warn: false

		children = [
			worker(ChatServer.TcpServer, []),
			worker(ChatServer.ChannelManager, [])
		]

		sup_opts = [strategy: :one_for_one, name: ChatServer.Supervisor]

		Supervisor.start_link children, sup_opts
	end

end

defmodule ChatServer.TcpServer do

	def start_link do
		opts = [port: 9000]
		{:ok, _} = :ranch.start_listener :chat_server, 100, :ranch_tcp, opts, ChatServer.TcpHandler, []
	end
	
end

defmodule ChatServer.TcpHandler do

	defmodule ConnState do
		defstruct user_name: nil, channels: []
	end

	def start_link(ref, socket, transport, opts) do
		pid = spawn_link(__MODULE__, :init, [ref, socket, transport, opts])
		{:ok, pid}
	end

	def init(ref, socket, transport, _opts) do
		:ok = :ranch.accept_ack ref
		:inet.setopts socket, [packet: 4, active: true]

		id = :crypto.rand_uniform(10000, 100000)
		user_name = "user-#{id}"
		send self, {:login, user_name}
		Logger.debug "#{user_name} connected."
		loop(socket, transport, %ConnState{ user_name: user_name })
	end

	def shutdown(socket, transport) do
		transport.close socket
	end

	def handle_message({:join, user, channel_name}, channels) do
		ChatServer.Channel.join channel_name, user
		[ channel_name | channels ]
	end

	def handle_message({:send, user, channel_name, message}, channels) do
		ChatServer.Channel.send_message channel_name, user, message
		channels
	end

	def loop(socket, transport, st) do
		receive do
			{:tcp, ^socket, blob} ->
				message = :erlang.binary_to_term blob
				channels = handle_message message, st.channels
				loop socket, transport, %{ st | channels: channels }
			{:tcp_closed, ^socket} ->
				Logger.debug "Client #{st.user_name} disconnected"
				Enum.each st.channels, fn channel_name ->
					ChatServer.Channel.leave channel_name, st.user_name
				end
				shutdown socket, transport
			message -> # unsafe
				blob = :erlang.term_to_binary message
				transport.send socket, blob
				loop socket, transport, st
		end
	end
end

defmodule ChatServer.Channel do

	defstruct name: "unknown-channel", user_index: %{}  

	alias ChatServer.Channel, as: Channel
	alias ChatServer.ChannelManager, as: ChannelManager

	use GenServer 
	
	def start_link name do
		GenServer.start_link(Channel, [name])
	end

	def init [channel_name] do
		{:ok, %Channel{name: channel_name}}
	end

	def handle_cast({:join, user_name, socket_pid}, channel) do
		user_names = Map.keys channel.user_index
		send socket_pid, {:users, channel.name, user_names}
		Enum.each channel.user_index, fn {_, socket_pid} ->
			send socket_pid, {:user_joined, channel.name, user_name}
		end
		channel = %{ channel | user_index: Map.put(channel.user_index, user_name, socket_pid) }
		{:noreply, channel}
	end

	def handle_cast({:send_message, user_name, message}, channel) do
		case Map.get channel.user_index, user_name do
			nil ->
				:ok
			_ ->
				Enum.each channel.user_index, fn {_, socket_pid} ->
					send socket_pid, {:message, channel.name, user_name, message}
				end
		end
		{:noreply, channel}
	end

	def handle_cast({:leave, user_name}, channel) do
		channel = %{ channel | user_index: Map.delete(channel.user_index, user_name)}
		Enum.each channel.user_index, fn {_, socket_pid} ->
			send socket_pid, {:user_left, channel.name, user_name}
		end
		{:noreply, channel}
	end

	# Public API

	def join(channel_name, user) do
		pid = ChannelManager.get_channel channel_name
		GenServer.cast pid, {:join, user, self}
	end

	def leave(channel_name, user) do
		pid = ChannelManager.get_channel channel_name
		GenServer.cast pid, {:leave, user}
	end

	def send_message(channel_name, user, message) do
		pid = ChannelManager.get_channel channel_name
		GenServer.cast pid, {:send_message, user, message}
	end

end

defmodule ChatServer.ChannelManager do

	def start_link do
		Agent.start_link(fn -> %{} end, [name: :channel_manager])
	end

	def get_channel channel_name do
		Agent.get_and_update :channel_manager, fn channels ->
			case Map.get channels, channel_name do
				nil ->
					{:ok, pid} = ChatServer.Channel.start_link channel_name
					{pid, Map.put(channels, channel_name, pid)}
				pid ->
					{pid, channels}
			end
		end
	end

end