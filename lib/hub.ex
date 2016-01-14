defmodule Nerves.Hub do
  
  @moduledoc """
  Implements a heirarchial key-value store with publish/watch semanitcs
  at each node of the heirarchy. 
  
  A specific location on a hub is called a __point__, a term borrowed from
  SCADA and DCS industrial control systems.  Points are defined by a __path__,
  which is a list of atoms.  

  Processes can publish state at any point on a hub (update), and subscribe to
  observe state changes at that point (watch). By doing so they will get
  notified whenever the point or anything below it changes. 
  
  Procesesses can also register as handlers for a __requests__ for a point. A
  process that hanldes requests for a point is called a __manager__.

  Hub keeps a sequence ID for each change to state, and this is stored as part
  of the state graph, so that the hub can answer the question: "show me all
  state that has changed since sequence XXX"

  ** Limitations and areas for improvement **

  Right now the store is only in memory, so a restart removes all data
  from the store.   All persistence must be implemented separately

  There is currently no change history or playback history feature.

  ## Examples

  Basic Usage:

     # Start the Hub GenServer
     iex> Hub.start
     {:ok, #PID<0.127.0>}
     # Put [status: :online] at path [:some, :point]
     iex(2)> Hub.put [:some,:point], [status: :online]
     {:changes, {"05142ef7fe86a86D2471CA6869E19648", 1},
     [some: [point: [status: :online]]]}
     # Fetch all values at path [:some, :point]
     Hub.fetch [:some, :point]
     {{"05142ef7fe86a86D2471CA6869E19648", 1}, [status: :online]}
     # Get particular value :status at [:some, :point]
     Hub.get [:some, :point], :status
     :online
"""

  import Nerves.Hub.Helpers
  alias Nerves.Hub.Server
  
  @proc_path_key {:agent, :path}

  def start() do
    start([],[])
  end

  def start_link() do
    start_link([], [])
  end

  @doc "Start the Hub GenServer"
  def start(_,_) do
    case GenServer.start(Server, [], name: Server) do
      {:error, {:already_started, pid}} ->
        {:ok, pid}
      ret ->
        ret
    end
  end

  @doc "Start the Hub GenServer with link to calling process"
  def start_link(_,_) do
    case GenServer.start_link(Server, [], name: Server) do
      {:error, {:already_started, pid}} ->
        {:ok, pid}
      ret ->
        ret
    end
  end

  @doc """
  Request a change to the path in the hub. The Manager is forwarded the request
  and is responsible for handling it. If no manager is found a timeout will
  occur.

  ## Examples

  ```
  iex> Hub.request [:some, :point], [useful: :info]
  {:changes, {"0513b7725c5436E67975FB3A13EB3BAA", 2},
   [some: [point: [useful: :info]]]}
  ```
  """
  def request(path, request, context \\ []) do
    atomic_path = atomify(path)
    {:ok, {manager_pid, _opts}} = manager(atomic_path)
    GenServer.call(manager_pid, {:request, atomic_path, request, context})
  end

  @doc """
  Updates the path with the changes provided.

  ## Examples
  ```
  iex> Hub.update [:some, :point], [some: :data]
  {:changes, {"05142ef7fe86a86D2471CA6869E19648", 1},
   [some: [point: [some: :data]]]}
  ```
  """
  def update(path, changes, context \\ []) do
    GenServer.call(Server, {:update, atomify(path), changes, context})
  end

  @doc """
  Same as `update/3` except no context argument. See `update/3` for more
  information
  """
  def put(path, changes) do
    update(path, changes)
  end

  @doc """
  Associate the currrent process as the primary agent for the given
  path.  This binds/configures this process to the hub, and also sets
  the path as the "agent path" in the process dictionary.

  *Note:* The path provided must exist and have values stored before trying
  to master it.

  ## Examples

  ```
  iex> Hub.master [:some, :point]
  :ok
  """
  def master(path, options \\ []) do
    Process.put @proc_path_key, path
    update(path, [])
    manage(path, options)
    watch(path, [])
  end

  @doc """
  Similar to `master/2` but does not `watch` the path.

  ## Examples

  ```
  iex> Hub.manage [:some, :point], []
  :ok
  ```
  """
  def manage(path, options \\ []) do
    GenServer.call(Server, {:manage, atomify(path), options})
  end

  @doc """
  Retrieves the manager with options for the provided path.

  ## Examples

  ```
  iex> Hub.manager [:some, :point]
  {:ok, {#PID<0.125.0>, []}}
  ```
  """
  def manager(path) do
    GenServer.call(Server, {:manager, atomify(path)})
  end

  @doc """
  Returns the controlling agent for this path, or nil if none

  ## Examples
  ```
  iex> Hub.agent [:some, :point]
  #PID<0.125.0>
  ```
  """
  def agent(path) do
    case manager(path) do
      {:ok, {pid, _opts} } -> pid
      _ -> nil
    end
  end

  @doc """
  Adds the calling process to the @wch list of process to get notified of
  changes to the path specified.

  ## Examples
  ```
  iex> Hub.watch [:some, :point]
  :ok
  ```
  """
  def watch(path, options \\ []) do
    GenServer.call(Server, {:watch, atomify(path), options})
  end

  @doc """
  Removes the calling process from the @wch list of process to stop getting
  notified of changes to the path specified.

  ## Examples
  ```
  iex> Hub.unwatch [:some, :point]
  :ok
  ```
  """
  def unwatch(path) do
    GenServer.call(Server, {:unwatch, atomify(path)})
  end

  @doc """
  Dumps the entire contents of the hub graph, including "non human" information.

  ## Examples
  ```
  iex> Hub.dump
  {{"05142ef7fe86a86D2471CA6869E19648", 1},
    [some: {1, [point: {1, [mgr@: {#PID<0.125.0>, []}, some: {1, :data}]}]}]}
  ```
  """
  def dump(path \\ []) do
    GenServer.call(Server, {:dump, atomify(path)})
  end

  @doc """
  Gets the value at the specified path with the specified key.

  ## Examples
  ```
  iex> Hub.get [:some, :point], :status
  :online
  ```
  """
  def get(path, key) do
    {_vers, dict} = fetch(path)
    Dict.get dict, key
  end

  @doc """
  Gets all the "human readable" key values pairs at the specified path.

  ## Examples
  ```
  iex>Hub.fetch [:some, :point]
  {{"05142ef7fe86a86D2471CA6869E19648", 1}, [some: :data]}
  ```
  """
  def fetch(path \\ []), do: deltas({:unknown, 0}, path)

  @doc """
  Gets the changes from the provided sequence counter on the path to its current
  state.

  The sequence counter is retured on calls to `get/1`, `put/2`, `update/3`,
  `dump/1`, `fetch/1`

  ## Examples
  ```
  iex> Hub.deltas {"05142f977e209de63a768684291be964", 1}, [:some, :path]
  {{"05142f977e209de63a768684291be964", 2}, [some: :new_data]}

  iex> Hub.deltas {:undefined, 0}, [:some, :path]
  #Returns all changes
  ```
  """
  def deltas(seq, path \\ []) do
    GenServer.call(Server, {:deltas, seq, atomify(path)})
  end

end
