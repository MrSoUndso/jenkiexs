defmodule Jenkiexs.Builds.Monitor do
  alias Jenkiexs.Builds
  alias Jenkiexs.Jobs.Build

  @queue_time 2_000
  @after_build_duration_time 1_000

  def monitor(%Build{estimated_duration: duration} = build) do
    task = Task.async(fn ->
      check(build, duration + @queue_time)
    end)

    {:ok, task}
  end

  defp check(build, timeout) do
    Process.sleep(timeout)
    case Builds.details(build) do
      {:ok, %{building?: false} = completed_build} ->
        {:ok, completed_build}
      _ ->
        check(build, @after_build_duration_time)
    end
  end

end