defmodule WeaverTest do
  use ExUnit.Case
  doctest Weaver

  test "fixed_masks with [500, 100, 100]" do
    input = [500, 100, 100]
    out = Weaver.fixed_masks(input)

    assert out == [
             %{machines: 500, addr: "172.16.0.0", prefix: 16},
             %{machines: 100, addr: "192.168.0.0", prefix: 24},
             %{machines: 100, addr: "192.168.1.0", prefix: 24}
           ]
  end

  # VLSM separado
  test "vlsm_separated with [500, 100, 100]" do
    input = [500, 100, 100]
    out = Weaver.vlsm_separated(input)

    assert out == [
             %{machines: 500, addr: "192.168.0.0", prefix: 23},
             %{machines: 100, addr: "192.168.2.0", prefix: 25},
             %{machines: 100, addr: "192.168.3.0", prefix: 25}
           ]
  end

  # VLSM sequencial
  test "vlsm_sequential with [500, 100, 100]" do
    input = [500, 100, 100]
    out = Weaver.vlsm_sequential(input)

    assert out == [
             %{machines: 500, addr: "192.168.0.0", prefix: 23},
             %{machines: 100, addr: "192.168.2.0", prefix: 25},
             %{machines: 100, addr: "192.168.2.128", prefix: 25}
           ]
  end
end
