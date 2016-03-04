
defmodule ChatClient do
	
	def start_prompt socket_pid do
		spawn_link __MODULE__, :prompt, [socket_pid]
	end

	def prompt socket_pid do
		data = IO.gets "> "
		case String.split data do
			["quit" | _ ] ->
				:ok
				send socket_pid, :close
			["join", channel] ->
				send socket_pid, {:join, channel}
				prompt socket_pid
			[channel | message_frag] ->
				message = Enum.join message_frag, " "
				send socket_pid, {:send, channel, message}
				prompt socket_pid
		end
		
	end

	def start do
		{:ok, socket} = :gen_tcp.connect 'localhost', 9000, [:binary, packet: 4, active: true]
		start_prompt self

		socket_loop socket, nil
	end

	def handle_message({:login, user_name}, nil) do
		IO.puts "Logged as '#{user_name}'"
		user_name
	end

	def handle_message({:user_joined, channel, new_user_name}, user_name) do
		IO.puts "'#{new_user_name}' joined channel '#{channel}'"
		user_name
	end

	def handle_message({:user_left, channel, left_user_name}, user_name) do
		IO.puts "'#{left_user_name}' left channel '#{channel}'"
		user_name
	end

	def handle_message({:users, channel, user_list}, user_name) do
		users = Enum.join user_list, " "
		IO.puts "[#{channel}] users: #{users}"
		user_name
	end

	def handle_message({:message, channel, user, message}, user_name) do
		IO.puts "[#{channel}] #{user}: #{message}"
		user_name
	end

	def socket_loop(socket, user) do
		receive do
			{:tcp, ^socket, blob} ->
				message = :erlang.binary_to_term blob
				user = handle_message message, user
				socket_loop socket, user
			{:tcp_closed, ^socket} ->
				:gen_tcp.close socket
			{:join, channel} ->
				message = {:join, user, channel}
				:gen_tcp.send(socket, :erlang.term_to_binary message)
				socket_loop socket, user
			{:send, channel, message} ->
				message = {:send, user, channel, message}
				:gen_tcp.send(socket, :erlang.term_to_binary message)
				socket_loop socket, user
			:close ->
				:gen_tcp.close socket
		end
	end

end

ChatClient.start