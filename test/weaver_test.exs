defmodule WeaverTest do
  use ExUnit.Case
  import Bitwise
  doctest Weaver

  # helpers
  defp ip_to_int(addr) do
    [a, b, c, d] = addr |> String.split(".") |> Enum.map(&String.to_integer/1)
    Weaver.ip_tuple_to_int({a, b, c, d})
  end

  defp block_size(prefix), do: 1 <<< (32 - prefix)

  describe "fixed_masks/1 (exemplos)" do
    test "[500, 100, 100]" do
      input = [500, 100, 100]
      out = Weaver.fixed_masks(input)

      assert out == [
               %{machines: 500, addr: "172.16.0.0", prefix: 16, mask: "255.255.0.0"},
               %{machines: 100, addr: "192.168.0.0", prefix: 24, mask: "255.255.255.0"},
               %{machines: 100, addr: "192.168.1.0", prefix: 24, mask: "255.255.255.0"}
             ]
    end
  end

  describe "vlsm_separated/1 (exemplos)" do
    test "[500, 100, 100]" do
      input = [500, 100, 100]
      out = Weaver.vlsm_separated(input)

      assert out == [
               %{machines: 500, addr: "192.168.0.0", prefix: 23, mask: "255.255.254.0"},
               %{machines: 100, addr: "192.168.2.0", prefix: 25, mask: "255.255.255.128"},
               %{machines: 100, addr: "192.168.3.0", prefix: 25, mask: "255.255.255.128"}
             ]
    end
  end

  describe "vlsm_sequential/1 (exemplos)" do
    test "[500, 100, 100]" do
      input = [500, 100, 100]
      out = Weaver.vlsm_sequential(input)

      assert out == [
               %{machines: 500, addr: "192.168.0.0", prefix: 23, mask: "255.255.254.0"},
               %{machines: 100, addr: "192.168.2.0", prefix: 25, mask: "255.255.255.128"},
               %{machines: 100, addr: "192.168.2.128", prefix: 25, mask: "255.255.255.128"}
             ]
    end
  end

  describe "VLSM invariants" do
    test "sequential: no overlap, aligned, within 192.168.0.0/16" do
      input = [500, 300, 200, 100, 50, 50, 10, 1, 2, 254, 255]
      rows = Weaver.vlsm_sequential(input)

      base_start = ip_to_int("192.168.0.0")
      base_end = ip_to_int("192.168.255.255")

      segments =
        rows
        |> Enum.map(fn %{addr: addr, prefix: p} ->
          start = ip_to_int(addr)
          size = block_size(p)
          {start, start + size - 1, size, p}
        end)
        |> Enum.sort_by(fn {s, _e, _sz, _p} -> s end)

      # alignment and bounds
      Enum.each(segments, fn {s, e, size, _p} ->
        assert rem(s, size) == 0
        assert s >= base_start
        assert e <= base_end
      end)

      # non-overlap (contiguous allowed)
      Enum.reduce(segments, nil, fn seg, prev ->
        if prev do
          {_ps, pe, _psz, _pp} = prev
          {s, _e, _sz, _p} = seg
          assert pe < s
        end

        seg
      end)
    end
  end

  describe "Erros e limites" do
    test "entradas inválidas levantam erro" do
      assert_raise ArgumentError, fn -> Weaver.fixed_masks([0]) end
      assert_raise ArgumentError, fn -> Weaver.vlsm_separated([-1]) end
      assert_raise ArgumentError, fn -> Weaver.vlsm_sequential([:bad]) end
    end

    test "hosts 1 e 2 forçam /30 (política atual)" do
      out = Weaver.vlsm_sequential([1, 2])
      assert Enum.all?(out, &(&1.prefix == 30))
    end

    test "254 cabe em /24; 255 exige prefixo menor que /24" do
      [n254, n255] = Weaver.vlsm_sequential([254, 255])
      assert n254.prefix == 24
      assert n255.prefix < 24
    end

    test "lista vazia retorna lista vazia" do
      assert Weaver.fixed_masks([]) == []
      assert Weaver.vlsm_separated([]) == []
      assert Weaver.vlsm_sequential([]) == []
    end

    test "fixed_masks: overflow de /16 ao pedir 17 redes grandes" do
      msg = "Excedeu a capacidade de /16"

      assert_raise ArgumentError, ~r/#{msg}/, fn ->
        Weaver.fixed_masks(List.duplicate(500, 17))
      end
    end

    test "fixed_masks: overflow de /24 ao pedir 257 redes pequenas" do
      msg = "Excedeu a capacidade de /24"

      assert_raise ArgumentError, ~r/#{msg}/, fn ->
        Weaver.fixed_masks(List.duplicate(100, 257))
      end
    end

    test "VLSM: rede que exige /15 excede 192.168.0.0/16" do
      assert_raise ArgumentError, ~r/Alocação excede 192\.168\.0\.0\/16/, fn ->
        Weaver.vlsm_sequential([65_535])
      end
    end
  end
end
