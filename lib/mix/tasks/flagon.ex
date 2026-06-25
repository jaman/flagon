defmodule Mix.Tasks.Flagon do
  @shortdoc "Launch the Flagon TUI"

  @moduledoc """
  Launches the Flagon terminal UI.

      mix flagon
      mix flagon --servers ~/.config/flagon/servers.json
      mix flagon --connection kdb://localhost:5001

  Options:

    * `--servers PATH` — load a hierarchical server list (`.json` or `.txt`)
    * `--connection STRING` — add a connection from a URI (repeatable)
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} =
      OptionParser.parse(argv, strict: [servers: :string, connection: :keep])

    Flagon.start(opts)
  end
end
