# this module based on original hub.erl by ghitchens circa 2012
# 
# ghitchens wrote initial erlang version as hub.erl
# captchrisd ported to elixir hub.ex
# ghitchens refactored from hub.ex
#
# still needs serious elixirification and cleanup, move to maps or HashDict

# If a value at any given path is a proplist (tested as a list whose first
# term is a tuple, or an empty list).
#
# some special keys that can appea
#
# mgr@        list of dependents in charge of point in graph
# wch@        list of dependents to be informed about changes
#

defmodule Nerves.Hub.OrdDictTree do

  @moduledoc false
  import Nerves.Hub.Helpers

  def new, do: :orddict.new

  ## manage ownership of this point
  ##
  ## TODO: un-manage?  handle errors if already manageed?   Security?
  def manage([], {{from_pid, _ref}, opts}, tree) do
    :orddict.store(:mgr@, {from_pid, opts}, tree)
  end

  def manage([h|t], {from, opts}, tree) do
    case :orddict.find(h, tree) do
      :error -> nil
      {:ok, {seq, st}} ->
        stnew = manage(t, {from, opts}, st)
        :orddict.store(h, {seq, stnew}, tree)
    end
  end

  def manage(point, f, tree), do: manage([point], f, tree)

  ## manager(Point, Tree) -> {ok, {Process, Options}} | undefined
  ##
  ## return the manageling process and options for a given point on the
  ## dictionary tree, if the manager was set by manage(...).
  def manager([], tree), do: :orddict.find(:mgr@, tree)

  def manager([h|t], tree) do
    case :orddict.find(h, tree) do
      :error -> nil
      {:ok, {_seq, sub_tree}} -> manager(t, sub_tree)
    end
  end

  def manager(point, tree), do: manager([point], tree) 
 
  ## watch(Path, Subscription, Tree)
  ##
  ## Subscription is a {From, watchParameters} tuple that is placed on
  ## the wch@ key at a node in the tree.  Adding a subscription doesn't
  ## currently cause any notificaitions, although that might change.
  ##
  ## REVIEW: could eventually be implemented as a special form of update by
  ## passing something like {append, Subscription, [notifications, false]}
  ## as the value, or maybe something like a function as the value!!! cool?

  def watch([], {from, opts}, tree) do
    {from_pid, _ref} = from
    subs = case :orddict.find(:wch@, tree) do
      {:ok, l} when is_list(l) ->
        :orddict.store(from_pid, opts, l)
      _ ->
        :orddict.store(from_pid, opts, :orddict.new())
    end
    {:ok, :orddict.store(:wch@, subs, tree)}
  end

  def watch([h|t], {from, opts}, tree) do
    case :orddict.find(h, tree) do
      {:ok, {seq, st}} ->
        case watch(t, {from, opts}, st) do
          {:ok, stnew} ->
            {:ok, :orddict.store(h, {seq, stnew}, tree)}
          {:error, reason} -> {:error, reason}
        end
      _ -> {:error, :nopoint}
    end
  end

  ## unwatch(Path, releaser, Tree) -> Tree | notfound
  ##
  ## removes releaser from the dictionary tree
  def unwatch([], unsub, tree) do
    {from_pid, _ref} = unsub
    case :orddict.find(:wch@, tree) do
      {:ok, old_subs} ->
        {:ok, :orddict.store(:wch@, :orddict.erase(from_pid, old_subs), tree)}
      _ -> {:error, :no_wch}
    end
  end

  def unwatch([h|t], unsub, tree) do
    case :orddict.find(h, tree) do
      {:ok, {seq, st}} ->
        case unwatch(t, unsub, st) do
          {:ok, stnew} ->
            {:ok, :orddict.store(h, {seq, stnew}, tree)}
          {:error, reason} -> {:error, reason}
        end
      _ -> {:error, :nopoint}
    end
  end

  ## update(PathList,ProposedChanges,Tree,Context) -> {ResultingChanges,NewTree}
  ##
  ## Coding Abbreviations:
  ##
  ## PC,RC    Proposed Changes, Resulting Changes (these are trees)
  ## P,PH,PT  Path/Path Head/ Path Tail
  ## T,ST     Tree,SubTree
  ## C        Context - of the form {Seq, Whatever} where whatever is
  ##          any erlang term - gets threaded unmodified through update
  def update([], pc, t, c) do
    if is_map(pc), do: pc = Dict.to_list(pc)
    uf = fn(key, value, {rc, dict}) ->
      case :orddict.find(key, dict) do
        {:ok, {_, val}} when val == value ->
          {rc, dict}
        _ when is_list(value) ->
          {rcsub, new_dict} = update(atomify([key]), value, dict, c)
          {(rc ++ rcsub), new_dict}
        _ ->
          {seq, _} = c
          {rc ++ [{key, value}], :orddict.store(atomify(key),
																								{seq, value}, dict)}
      end
    end
    {cl, tnew} = :orddict.fold(uf, {[], t}, pc)
    send_notifications(cl, tnew, c)
    {cl, tnew}
  end

  def update([head|tail], pc, t, c) do
    st = case :orddict.find(head, t) do
      {:ok, {_seq, l}} when is_list(l) and (length(l) > 0) and is_tuple(hd(l)) -> 
        l
      {:ok, _} -> 
        :orddict.new
      :error -> 
        :orddict.new
    end
    {rcsub, stnew} = update(tail, pc, st, c)
    case rcsub do
      [] -> {[], t}
      y ->
        rc = [{head, y}]
        {seq, _} = c
        t = :orddict.store(head, {seq, stnew}, t)
        send_notifications(rc, t, c)
        {rc, t}
    end
  end

  def dump([], tree), do: tree

  def dump([h|t], tree) do
    {:ok, {_seq, sub_tree}} = :orddict.find(h, tree)
    dump(t, sub_tree)
  end

  def deltas(since, [], tree) do
    fn_filter = fn(key, val) ->
      case {key, val} do
        {:wch@, _} -> false
        {:mgr@, _} -> false
        {_key, {seq, _val}} -> (seq > since)
        _ -> true
      end
    end
    fn_recurse = fn(key, {_seq, val}) ->
      case {key, val} do
        {:wch@, _} -> val
        {:mgr@, _} -> val
        {_, l} when is_list(l) and (length(l) > 0) and is_tuple(hd(l)) ->
          deltas(since, [], l)
        _ -> val
      end
    end
    :orddict.map(fn_recurse, :orddict.filter(fn_filter, tree))
  end

  def deltas(since, [h|t], tree) do
    case :orddict.find(h, tree) do
      {:ok, {_seq, sub_tree}} when is_list(sub_tree) and (length(sub_tree) > 0) and is_tuple(hd(sub_tree)) ->
        deltas(since, t, sub_tree)
      _ -> :error
    end
  end

  # Send notification to all watchers who called `watch/1`
  defp send_notifications([], _, _), do: :pass
  defp send_notifications(changes, tree, context) do
    case :orddict.find(:wch@, tree) do
      {:ok, subs} when is_list(subs) ->
        :orddict.map(fn(pid, opts) ->
          send(pid, {:notify, opts, changes, context})
        end, subs)
      _ -> :pass
    end
  end

end
