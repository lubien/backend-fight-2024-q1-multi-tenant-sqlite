defmodule BackendFight.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :backend_fight

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn repo ->
        Ecto.Migrator.run(repo, :up, all: true)
        repo.query("PRAGMA threads = 4;")
        repo.query("PRAGMA automatic_indexing = TRUE;")
        repo.query("PRAGMA count_changes = FALSE;")
        repo.query("PRAGMA encoding = \"UTC-8\";")
        repo.query("PRAGMA ignore_check_constraints = TRUE;")
        repo.query("PRAGMA incremental_vacuum = 0;")
        repo.query("PRAGMA legacy_file_format = FALSE;")
        repo.query("PRAGMA optimize = On;")
      end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
