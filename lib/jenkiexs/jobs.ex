defmodule Jenkiexs.Jobs do
  alias Jenkiexs.{Builds, Client}
  alias Jenkiexs.Jobs.{Build, Job}

  @type job_name() :: binary()

  @spec all() :: {:ok, list(Job.t())} | {:error, reason :: binary()}
  def all do
    case Client.get!("/api/json?tree=jobs[name,description,fullName,displayName,fullDisplayName,inQueue,buildable,disabled,nextBuildNumber,property[parameterDefinitions[name,defaultParameterValue[value]]]]") do
      %{status_code: 200, body: body} ->
        jobs = body
          |> Map.get("jobs")
          |> Enum.map(&create_job/1)
        {:ok, jobs}
      response ->
        {:error, inspect(response)}
    end
  end

  @spec all!() :: list(Job.t())
  def all! do
    case all() do
      {:ok, jobs} -> jobs
      {:error, reason} -> raise reason
    end
  end

  @spec details(Job.t() | job_name()) :: {:ok, Job.t()} | {:error, reason :: binary()}
  def details(%Job{name: job_name} = _job), do: details(job_name)
  def details(job_name) do
     case Client.get!("/job/#{job_name}/api/json") do
       %{status_code: 200, body: body} ->
         {:ok, create_job(body)}
      response ->
        {:error, inspect(response)}
     end
  end

  @spec details!(Job.t() | job_name()) :: Job.t()
  def details!(%Job{name: job_name} = _job), do: details!(job_name)
  def details!(job_name) do
    case details(job_name) do
      {:ok, job} -> job
      {:error, reason} -> raise reason
    end
  end

  @spec build(Job.t() | job_name(), params :: keyword()) :: {:ok, Build.t()} | {:error, reason :: binary()}
  def build(job, params \\ [])
  def build(%Job{name: job_name} = _job, params),
    do: build(job_name, params)
  def build(job_name, params) do
    {build_endpoint, req_body} =
      if Enum.empty?(params) do
        {"/job/#{job_name}/build", ""}
      else
        {"/job/#{job_name}/buildWithParameters", {:form, params}}
      end

    with {:ok, %{status_code: 201}} <- Client.post(build_endpoint, req_body),
      {:ok, job} <- details(job_name)
    do
      Builds.last(job)
    else
      {:error, reason} ->
        {:error, inspect(reason)}
      error ->
        {:error, inspect(error)}
    end
  end

  @spec build!((Job.t() | job_name()), params :: keyword()) :: Build.t()
  def build!(job, params \\ [])
  def build!(%Job{name: job_name} = _job, params), do: build!(job_name, params)
  def build!(job_name, params) do
    case build(job_name, params) do
      {:ok, build} -> build
      {:error, reason} -> reason
    end
  end

  @spec build_monitored((Job.t() | job_name()), keyword())
    :: {:ok, Task.t()} | {:error, reason :: binary()}
  def build_monitored(job, params \\ []) do
    case build(job, params) do
      {:error, reason} ->
        {:error, reason}
      {:ok, build} ->
        task = Builds.monitor(build)
        {:ok, task}
    end
  end

  @spec get_console_text(Job.t() | job_name()) :: {:ok, binary()} | {:error, reason :: binary()}
  def get_console_text(job, build_number \\ :last_build)
  def get_console_text(%Job{name: job_name} = _job, %Build{number: build_num}),
    do: get_console_text(job_name, build_num)
  def get_console_text(%Job{name: job_name} = _job, build_number),
    do: get_console_text(job_name, build_number)
  def get_console_text(job_name, build_number) do
    build = if is_integer(build_number), do: build_number, else: "lastBuild"
    Client.get!("/job/#{job_name}/#{build}/consoleText")
    |> process_response_log_text()
  end

  @spec get_console_text!(Job.t() | job_name()) :: binary()
  def get_console_text!(job, build_number \\ :last_build)
  def get_console_text!(%Job{name: job_name} = _job, %Build{number: build_num}),
    do: get_console_text!(job_name, build_num)
  def get_console_text!(%Job{name: job_name} = _job, build_number),
    do: get_console_text!(job_name, build_number)
  def get_console_text!(job_name, build_number) do
    case get_console_text(job_name, build_number) do
      {:ok, text} -> text
      {:error, reason} -> raise reason
    end
  end

  @spec get_console_output(Job.t() | job_name()) :: {:ok, binary()} | {:error, reason :: binary()}
  def get_console_output(job, build_number \\ :last_build, output \\ :text)
  def get_console_output(%Job{name: job_name} = _job, %Build{number: build_num}, output),
    do: get_console_output(job_name, build_num, output)
  def get_console_output(%Job{name: job_name} = _job, build_number, output),
    do: get_console_output(job_name, build_number, output)
  def get_console_output(job_name, build_num, output) do
    mode = if output == :text, do: "Text", else: "Html"
    build = if is_integer(build_num), do: build_num, else: "lastBuild"
    Client.get!("/job/#{job_name}/#{build}/logText/progressive#{mode}?start=0")
    |> process_response_log_text()
  end

  @spec get_console_output!(Job.t() | job_name()) :: binary()
  def get_console_output!(job, build_number \\ :last_build, output \\ :text)
  def get_console_output!(%Job{name: job_name} = _job, %Build{number: build_num}, output),
    do: get_console_output!(job_name, build_num, output)
  def get_console_output!(%Job{name: job_name} = _job, build_number, output),
    do: get_console_output!(job_name, build_number, output)
  def get_console_output!(job_name, build_num, output) do
    case get_console_output(job_name, build_num, output) do
      {:ok, console_output} -> console_output
      {:error, reason} -> raise reason
    end
  end

  defp process_response_log_text(%{status_code: 200, body: body}) do
    {:ok, body}
  end

  defp process_response_log_text(response) do
    {:error, inspect(response)}
  end

  defp create_job(%{"_class" => class} = body) when class in ["org.jenkinsci.plugins.workflow.job.WorkflowJob"] do
    url = Map.get(body, "url")
    name = Map.get(body, "name")
    disabled = Map.get(body, "disabled")
    in_queue = Map.get(body, "inQueue", false)
    property = Map.get(body, "property", [])
    buildable = Map.get(body, "buildable")
    full_name = Map.get(body, "fullName")
    description = Map.get(body, "description")
    display_name = Map.get(body, "displayName")
    full_display_name = Map.get(body, "fullDisplayName")
    next_build_number = Map.get(body, "nextBuildNumber")

    build_parameters =
      property
      |> Enum.filter(&(Map.has_key?(&1, "parameterDefinitions")))
      |> Enum.flat_map(&(Map.get(&1, "parameterDefinitions")))
      |> Enum.map(fn
        %{"name" => name, "defaultParameterValue" => %{"value" => value}} ->
          {String.to_atom(name), value}
        %{"name" => name} ->
          {String.to_atom(name), nil}
        end)
      |> Map.new()

    %{path: path} = unless is_nil(url), do: URI.parse(url)
    path =
      if not is_nil(path) and String.starts_with?(path, "/job")
        do
          path
          |> String.replace("/job/", "", global: false)
          |> String.replace_trailing("/", "")
        else
          path
        end

    %Job{
      name: path || name,
      path: path || name,
      full_name: full_name,
      display_name: display_name,
      full_display_name: full_display_name,
      in_queue?: in_queue,
      disabled?: disabled,
      buildable?: buildable,
      description: description,
      build_parameters: build_parameters,
      next_build_number: next_build_number,
      last_build_number: next_build_number - 1
    }
  end

  defp create_job(_), do: %Job{}
end