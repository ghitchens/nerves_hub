defmodule Nerves.Hub.Server do

  use GenServer

  require Logger
  require Record

  alias Nerves.Hub.OrdDictTree, as: Tree
  alias Nerves.Lib.UUID

  defmodule State do
    defstruct gtseq: 0, vlock: nil, dtree: nil
  end

  def init(_args) do
    {:ok, %State{ gtseq: 0, vlock: UUID.generate, dtree: Tree.new}}
  end

  def terminate(:normal, _state), do: :ok
  def terminate(reason, _state), do: reason

  def code_change(_old_ver, state, _extra), do: {:ok, state}

  def handle_info(msg, state) do
    Logger.debug "#{__MODULE__} got unexpected message: #{inspect msg}"
    {:noreply, state}
  end

  def handle_call(:terminate, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @doc false
  def handle_call({:manage, path, opts}, from, state) do
    case Tree.manage(path, {from, opts}, state.dtree) do
      tnew when is_list(tnew) ->
        {:reply, :ok, %State{state | dtree: tnew}}
      _ ->
        {:reply, :error, state}
    end
  end

  @doc false
  def handle_call({:manager, path}, _from, state) do
    {:reply, Tree.manager(path, state.dtree), state}
  end

  @doc false
  def handle_call({:watch, path, opts}, from, state) do
    case Tree.watch(path, {from, opts}, state.dtree) do
      {:ok, tnew} when is_list(tnew) ->
        {:reply,
          {:ok, {
            {state.vlock, state.gtseq},
            handle_vlocked_deltas({:unknown, 0}, path, state)
          }},
          %State{state | dtree: tnew}
        }
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @doc false
  def handle_call({:unwatch, path}, from, state) do
    case Tree.unwatch(path, from, state.dtree) do
      {:ok, tnew} when is_list(tnew) ->
        {:reply, :ok, %State{state | dtree: tnew}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @doc false
  def handle_call({:request, _key, _req}, _from, state) do
    {:reply, :ok, state}
  end

  @doc false
  def handle_call({:update, path, proposed, auth}, from, state) do
    seq = state.gtseq + 1
    ctx = {seq, [from: from, auth: auth]} #REVIEW .erl 233
    case Tree.update(path, proposed, state.dtree, ctx) do
      {[], _} ->
        {:reply, {:nochanges, {state.vlock, state.gtseq}, []}, state}
      {changed, new_tree} ->
        state = %State{state | dtree: new_tree, gtseq: seq}
        {:reply, {:changes, {state.vlock, seq}, changed}, state}
    end
  end

  @doc false
  def handle_call({:dump, path}, _from, state) do
    {:reply, {{state.vlock, state.gtseq}, Tree.dump(path, state.dtree)},state}
  end

  @doc false
  def handle_call({:deltas, seq, path}, _from, state) do
    {:reply, {{state.vlock, state.gtseq}, handle_vlocked_deltas(seq, path, state)}, state}
  end

  # Breaks apart the vlock information and calls Tree.deltas with the version
  # found or since the start (version 0)
  defp handle_vlocked_deltas({cur_vlock, since}, path, state) do
    case state.vlock do
      vlock when vlock == cur_vlock -> Tree.deltas(since, path, state.dtree)
      _ -> Tree.deltas(0, path, state.dtree)
    end
  end

end
