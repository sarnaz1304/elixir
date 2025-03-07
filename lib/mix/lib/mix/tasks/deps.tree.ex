defmodule Mix.Tasks.Deps.Tree do
  use Mix.Task

  @shortdoc "Prints the dependency tree"
  @recursive true

  @moduledoc """
  Prints the dependency tree.

      $ mix deps.tree

  If no dependency is given, it uses the tree defined in the `mix.exs` file.

  ## Command line options

    * `--only` - the environment to show dependencies for.

    * `--target` - the target to show dependencies for.

    * `--exclude` - exclude dependencies which you do not want to see printed. You can
      pass this flag multiple times to exclude multiple dependencies.

    * `--umbrella-only` - (since v1.17.0) only include the umbrella applications.
      This is useful when you have an umbrella project and want to see the
      relationship between the apps in the project.

    * `--format` - can be set to one of either:

      * `pretty` - uses Unicode code points for formatting the tree.
        This is the default except on Windows.

      * `plain` - does not use Unicode code points for formatting the tree.
        This is the default on Windows.

      * `dot` - produces a DOT graph description of the dependency tree
        in `deps_tree.dot` in the current directory.
        Warning: this will override any previously generated file.

  ## Examples

  Print the dependency tree for the `:test` environment:

      $ mix deps.tree --only test

  Exclude the `:ecto` and `:phoenix` dependencies:

      $ mix deps.tree --exclude ecto --exclude phoenix

  Only print the tree for the `:bandit` and `:phoenix` dependencies:

      $ mix deps.tree --include bandit --include phoenix

  """

  @switches [
    only: :string,
    target: :string,
    exclude: :keep,
    umbrella_only: :boolean,
    format: :string
  ]

  @impl true
  def run(args) do
    Mix.Project.get!()
    {opts, args, _} = OptionParser.parse(args, switches: @switches)

    dbg(Mix.Project.config())

    deps_opts =
      for {switch, key} <- [only: :env, target: :target],
          value = opts[switch],
          do: {key, :"#{value}"}

    deps = Mix.Dep.Converger.converge(deps_opts)

    root =
      case args do
        [] ->
          Mix.Project.config()[:app] ||
            Mix.raise("no application given and none found in mix.exs file")

        [app] ->
          app = String.to_atom(app)
          find_dep(deps, app) || Mix.raise("could not find dependency #{app}")
      end

    if opts[:format] == "dot" do
      callback = callback(&format_dot/1, deps, opts)
      Mix.Utils.write_dot_graph!("deps_tree.dot", "dependency tree", [root], callback, opts)

      """
      Generated "deps_tree.dot" in the current directory. To generate a PNG:

          dot -Tpng deps_tree.dot -o deps_tree.png

      For more options see http://www.graphviz.org/.
      """
      |> String.trim_trailing()
      |> Mix.shell().info()
    else
      callback = callback(&format_tree/1, deps, opts)
      Mix.Utils.print_tree([root], callback, opts)
    end
  end

  defp callback(formatter, deps, opts) do
    umbrella_only? = Keyword.get(opts, :umbrella_only, false)
    excluded = Keyword.get_values(opts, :exclude) |> Enum.map(&String.to_atom/1)

    if umbrella_only? && !Mix.Project.parent_umbrella_project_file() do
      Mix.raise("The --umbrella-only option can only be used in umbrella projects")
    end

    top_level = Enum.filter(deps, & &1.top_level)

    fn
      %Mix.Dep{app: app} = dep ->
        # Do not show dependencies if they were
        # already shown at the top level
        deps =
          if not dep.top_level && find_dep(top_level, app) do
            []
          else
            find_dep(deps, app).deps
          end

        {formatter.(dep), select_and_sort(deps, excluded, umbrella_only?)}

      app ->
        {{Atom.to_string(app), nil}, select_and_sort(top_level, excluded, umbrella_only?)}
    end
  end

  defp select_and_sort(deps, excluded, umbrella_only?) do
    deps
    |> filter_umbrella_only(umbrella_only?)
    |> Enum.reject(&(&1.app in excluded))
    |> Enum.sort_by(& &1.app)
  end

  defp filter_umbrella_only(deps, umbrella_only?) do
    if umbrella_only? do
      Enum.filter(deps, fn %Mix.Dep{opts: opts} -> opts[:in_umbrella] end)
    else
      deps
    end
  end

  defp format_dot(%{app: app, requirement: requirement, opts: opts}) do
    override =
      if opts[:override] do
        " *override*"
      else
        ""
      end

    requirement = requirement && requirement(requirement)
    {app, "#{requirement}#{override}"}
  end

  defp format_tree(%{app: app, scm: scm, requirement: requirement, opts: opts}) do
    override =
      if opts[:override] do
        IO.ANSI.format([:bright, " *override*"])
      else
        ""
      end

    requirement = requirement && "#{requirement(requirement)} "
    {app, "#{requirement}(#{scm.format(opts)})#{override}"}
  end

  defp requirement(%Regex{} = regex), do: "#{inspect(regex)}"
  defp requirement(binary) when is_binary(binary), do: binary

  defp find_dep(deps, app) do
    Enum.find(deps, &(&1.app == app))
  end
end
