defmodule Overdiscord.Commands do

  use Alchemy.Events

  def on_msg(%{author: %{id: "336892378759692289"}}) do
    # Ignore bot message
    :ok
  end
  def on_msg(%{author: %{bot: _true_or_false, username: username}, channel_id: "320192373437104130", content: content}=msg) do
    case content do
      "!list" -> Overdiscord.IRC.Bridge.list_users()
      "!"<>_ -> :ok
      content ->
        #IO.inspect("Msg dump: #{inspect msg}")
        IO.inspect("Sending message from Discord to IRC: #{username}: #{content}")
        irc_content = get_msg_content_processed(msg)
        Overdiscord.IRC.Bridge.send_msg(username, irc_content)
        Enum.map(msg.attachments, fn %{filename: filename, size: size, url: url, proxy_url: _proxy_url}=_attachment ->
          size = Sizeable.filesize(size, spacer: "")
          Overdiscord.IRC.Bridge.send_msg(username, "#{filename} #{size}: #{url}")
        end)
    end
  end
  def on_msg(msg) do
    IO.inspect(msg, label: :UnhandledMsg)
  end

  def on_msg_edit(%{author: %{id: "336892378759692289"}}) do
    # Ignore bot message
  end
  def on_msg_edit(%{author: %{bot: _true_or_false, username: username} = author, channel_id: "320192373437104130", content: content}=msg) do
    case content do
      "!" <> _ -> :ok
      content -> on_msg(%{msg | author: %{author | username: "#{username}{EDIT}"}})
    end
  end
  def on_msg_edit(msg) do
    IO.inspect(msg, label: :EditedMsg)
  end

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init(_) do
    use Overdiscord.Commands.Basic
    use Overdiscord.Commands.GT6
    use Overdiscord.Commands.GD
    Alchemy.Cogs.EventHandler.add_handler({:message_create, {__MODULE__, :on_msg}})
    Alchemy.Cogs.EventHandler.add_handler({:message_update, {__MODULE__, :on_msg_edit}})
    spawn(fn ->
      Process.sleep(5000)
      # Load entire userlist, at a rate of 100 per minutes because of discord limits
      Alchemy.Cache.load_guild_members(elem(Alchemy.Cache.guild_id(Overdiscord.IRC.Bridge.alchemy_channel()), 1), "", 0)
    end)
    {:ok, nil}
  end

  ## Helpers

  def get_msg_content_processed(%Alchemy.Message{channel_id: channel_id, content: content} = msg) do
    case Alchemy.Cache.guild_id(channel_id) do
      {:error, reason} ->
        IO.inspect("Unable to process guild_id: #{reason}\n\t#{msg}")
        content
      {:ok, guild_id} ->
        Regex.replace(~r/<@([0-9!]+)>/, content, fn full, user_id ->
          case Alchemy.Cache.member(guild_id, user_id) do
            {:ok, %Alchemy.Guild.GuildMember{user: %{username: username}}} ->
              "@#{username}"
            v ->
              case Alchemy.Client.get_member(guild_id, user_id) do
                {:ok, %Alchemy.Guild.GuildMember{user: %{username: username}}} ->
                  "@#{username}"
                err ->
                  IO.inspect("Unable to get member of guild: #{inspect v}")
                  full
              end
          end
        end)
    end
  end

end
