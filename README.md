# ChatServer

Simple chat server and client

### Run server

```
mix deps.get
iex -S mix
```

### Run client

```elixir chat_client.ex```

**Client commands**

`join CHANNEL`

Join a chat channel

`CHANNEL MESSAGE`

Send a message to a channel. Only user who joined previously can send messages.
