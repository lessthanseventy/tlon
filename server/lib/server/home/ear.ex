defmodule Server.Home.Ear do
  @moduledoc """
  The home inbox's ear: a voice note becomes text on this machine, never sent to a provider. The
  audio is the messenger's (`fetch/1`), made 16 kHz mono by `ffmpeg` and read by whisper.cpp's
  `whisper-cli` with the model at `:home_whisper_model` (`TLON_WHISPER_MODEL`, which the machine
  sets). With no model, hearing is refused. `:home_ffmpeg_cmd` and `:home_whisper_cmd` name other
  commands.
  """

  @doc "The words in the messenger's voice note `file`."
  @spec hear(String.t()) :: {:ok, String.t()} | {:error, term()}
  def hear(file) do
    messenger = Application.get_env(:server, :home_messenger, Server.Home.Telegram)

    with model when is_binary(model) <- Application.get_env(:server, :home_whisper_model) || {:error, :no_model},
         {:ok, audio} <- messenger.fetch(file) do
      transcribe(audio, model)
    end
  end

  @doc "The words in `audio` (any format ffmpeg reads) as whisper's `model` hears them; silence is an error."
  @spec transcribe(binary(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def transcribe(audio, model) do
    base = Path.join(System.tmp_dir!(), "ear-#{System.pid()}-#{System.unique_integer([:positive])}")
    {heard, wav} = {base <> ".oga", base <> ".wav"}

    try do
      File.write!(heard, audio)

      with {:ok, _} <- run(:home_ffmpeg_cmd, "ffmpeg", ~w(-loglevel error -y -i #{heard} -ar 16000 -ac 1 #{wav})),
           {:ok, out} <- run(:home_whisper_cmd, "whisper-cli", ["-m", model, "-f", wav, "-nt", "-np"]) do
        words(out)
      end
    after
      File.rm(heard)
      File.rm(wav)
    end
  end

  defp run(key, default, args), do: run(Application.get_env(:server, key, default), args)

  defp run(cmd, args) do
    # stdout alone: whisper-cli narrates its loading on stderr, which would be read as words
    case System.cmd(cmd, args) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, "#{cmd} exited #{code}: #{String.slice(out, 0, 200)}"}
    end
  rescue
    e in ErlangError -> {:error, "#{cmd}: #{Exception.message(e)}"}
  end

  # whisper marks what is not speech in brackets: [BLANK_AUDIO], [MUSIC]
  defp words(out) do
    out
    |> String.replace(~r/\[[^\]]*\]|\([^)]*\)/, " ")
    |> String.split()
    |> Enum.join(" ")
    |> case do
      "" -> {:error, :silence}
      words -> {:ok, words}
    end
  end
end
