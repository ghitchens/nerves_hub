defmodule Nerves.Hub.Test do
  use ExUnit.Case, async: true
  #doctest Nerves.Hub

  alias Nerves.Hub

  Hub.start

  test "hub is running and sorta works" do
    assert(Hub.dump())
  end

  test "hub handles basic updates and sequence numbers" do
    {{initial_lock, initial_seq}, _} = Hub.fetch
    result = Hub.update [ "kg7ga", "rig", "kw" ], [ "afgain": 32 ], []
    assert {:changes, new_ver, [kg7ga: [rig: [kw: [afgain: 32]]]] } = result
    {new_lock, new_seq} = new_ver
    assert is_integer(new_seq)
    assert new_seq > initial_seq
    assert new_lock == initial_lock
  end

  test "hub handles map arguments properly" do
    result = Hub.update ["foo"], %{this: %{is_a: "map"}}
    assert {:changes, _, [foo: [this: [is_a: "map"]]]} = result
  end

  test "hub handles setting and getting arrays" do
    changes ["a", "b", "c"], int_array: [2, 3, 5], array_of_arrays: [[2],[3,4],[5,6,7]]
    changes ["d", "e", "f"], empty_array: [], array_of_strings: ["23252", "2521"]
    changes ["a", "b", "c"], int_array: [2, 1, 5], array_of_arrays: [[2],[3,8],[5,6,7]]
    nochanges ["a", "b", "c"], int_array: [2, 1, 5], array_of_arrays: [[2],[3,8],[5,6,7]]
    changes ["a", "b", "c"], int_array: [2, 3, 5], array_of_arrays: [[2],[3,4],[5,6,7]]
    nochanges ["a", "b", "c"], int_array: [2, 3, 5], array_of_arrays: [[2],[3,4],[5,6,7]]
    nochanges ["d", "e", "f"], empty_array: [], array_of_strings: ["23252", "2521"]
  end

  test "setting to name or nil reports changes appropriately" do
    changes ["q", "r", "s"], nil_test_key: "this is a string"
    nochanges ["q", "r", "s"], nil_test_key: "this is a string"
    changes ["q", "r", "s"], some_test_key: :asymbol
    nochanges ["q", "r", "s"], some_test_key: :asymbol
    changes ["q", "r", "s"], nil_test_key: nil
    nochanges ["q", "r", "s"], nil_test_key: nil
  end

  test "hub handles setting and getting strings" do
    changes ["a", "b", "c"], basic_string: "hello world", weird_string: """
    This is a long string\302
    with weird characters \n and \205
    """
    changes ["a", "b", "c"], basic_string: "foo", weird_string: """
    another strange one
    """
  end

  test "Hub handles basic update and differencing correctly" do
    test_data = [ basic_key: "yes", another_key: "no", with: 3 ]
    test_rootkey = :nemo_temp_tests
    test_subkey = :some_sub_path
    test_path = [ test_rootkey, test_subkey ]
    expected_changes = [{test_rootkey, [{test_subkey, test_data}]}]
    {{initial_lock, initial_seq}, _} = Hub.fetch
    { resp_type, new_ver, resp_changes } = Hub.update test_path, test_data
    assert resp_type == :changes
    {new_lock, new_seq} = new_ver
    assert new_seq == (initial_seq + 1)
    assert new_lock == initial_lock
    assert resp_changes == expected_changes

    # now test difference engine!   write some new data where only one
    # field has changed, and then make sure only that field is reported
    # as changed.

    test_data2 = [ basic_key: "yes", another_key: "maybe", with: 3 ]
    test_changes2 = [ another_key: "maybe" ]
    expected_changes2 = [{test_rootkey, [{test_subkey, test_changes2}]}]
    { resp_type, resp_ver2, resp_changes } = Hub.update test_path, test_data2
    assert resp_type == :changes
    {resp_lock2, resp_seq2} = resp_ver2
    assert resp_seq2 == new_seq + 1
    assert resp_lock2 == initial_lock
    assert resp_changes == expected_changes2

 	  # now test case where we dont' make any changes, we should get back
 	  # :nochanges with an empty changelist

    { resp_type, resp_ver3, resp_changes } = Hub.update test_path, test_data2
    assert resp_type == :nochanges
    assert {initial_lock, (new_seq + 1)} == resp_ver3
    assert resp_seq2 == new_seq + 1
    assert resp_lock2 == initial_lock
    assert resp_changes == []
  end

  def changes(path, values) do
    {_, expected_changes} = path
      |> Enum.reverse
      |> Enum.map_reduce(values, fn(x, acc) ->
        {x, [{:erlang.binary_to_atom(x, :utf8), acc}]}
      end)
    assert {:changes, _new_ver, ^expected_changes} = Hub.update path, values
  end

  def nochanges(path, values) do
    assert {:nochanges, _new_ver, []} = Hub.update path, values
  end

  test "Hub handles watching" do
    path = [ :some, :test, :point ]
    Hub.update path, [ "test_data": [5, 16, "Some String"] ], []
    dump_result = Hub.fetch path
    {:ok, watch_result} = Hub.watch path
    assert dump_result == watch_result
  end

  test "Get method usage" do
    path = [ :some, :test, :point ]
    Hub.update path, [ "test_data": [5, 16, "Some String"] ], []
    new_result = Hub.get path
    assert new_result == [ "test_data": [5, 16, "Some String"] ]
    #DEPRECATED USAGE
    dep_result = Hub.get path, :test_data
    assert dep_result == [5, 16, "Some String"]
  end

  test "Put method" do
    path = [ :some, :test, :point ]
    res = Hub.put path, [ "test_data": [5, 16, "Some String"] ]
    assert res == :ok
  end
end
