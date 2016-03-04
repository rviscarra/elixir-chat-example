defmodule ChatServer.Mixfile do
  use Mix.Project

  def project do
    [app: :chat_server,
     version: "0.0.1",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps]
  end

  def application do
    [
      applications: [:logger, :crypto, :ranch],
      mod: {ChatServer, []}
    ]
  end

  defp deps do
    [
      {:ranch, git: "https://github.com/ninenines/ranch", tag: "1.2.1"},
      {:mochijson2, git: "https://github.com/bjnortier/mochijson2"}
    ]
  end
end
