defmodule Server.Home.EarTest do
  use ExUnit.Case, async: false

  alias Server.Home.Ear

  setup do
    dir = Path.join(System.tmp_dir!(), "ear-test-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      for key <- [:home_ffmpeg_cmd, :home_whisper_cmd, :home_whisper_model], do: Application.delete_env(:server, key)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  defp cli(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\n" <> body <> "\n")
    File.chmod!(path, 0o755)
    path
  end

  defp hears(dir, whisper) do
    Application.put_env(:server, :home_ffmpeg_cmd, cli(dir, "ffmpeg", ~s(for last; do :; done; cp "$5" "$last")))
    Application.put_env(:server, :home_whisper_cmd, cli(dir, "whisper", whisper))
  end

  test "the audio is converted, read with the model, and its words are tidied", %{dir: dir} do
    hears(
      dir,
      ~s(echo loading >&2; echo "$@" > #{dir}/args; cat "$4" > #{dir}/heard; printf ' [MUSIC]  Call the\\n dentist.  \\n')
    )

    assert Ear.transcribe("the audio", "/models/small.bin") == {:ok, "Call the dentist."}
    assert File.read!(Path.join(dir, "heard")) == "the audio"
    assert File.read!(Path.join(dir, "args")) =~ "-m /models/small.bin -f "
    assert Path.wildcard(Path.join(System.tmp_dir!(), "ear-#{System.pid()}-*")) == []
  end

  test "silence, and a command that fails, are errors", %{dir: dir} do
    hears(dir, "echo ' [BLANK_AUDIO]'")
    assert Ear.transcribe("the audio", "m") == {:error, :silence}

    hears(dir, "echo no model; echo loading >&2; exit 3")
    assert {:error, "/" <> why} = Ear.transcribe("the audio", "m")
    assert why =~ "exited 3: no model"
  end

  test "with no model on the machine nothing is fetched or heard" do
    assert Ear.hear("f1") == {:error, :no_model}
  end
end
