import unittest, nunroll, math, times, sequtils

suite "nunroll":

  let seed = int(times.cpuTime() * 10000000)
  echo "random seed ", seed
  math.randomize(seed)

  let getter = proc(i: int): nunroll.Item[int, int, int] {.noSideEffect.} = (i * 2, i * 4, i)

  # checks both the exposed iterator values (items and pair)
  # as well as the internal segment structure to make sure
  # the layout is what it should be
  proc checkList[I, S, V](list: nunroll.List[I, S, V], all: varargs[seq[V]]) =
    # first, check the segment structure
    var segment = list.head
    var flattened = newSeq[V]()
    for expected in all:
      for i, e in expected:
        check(segment.items[i].value == e)
        flattened.add(e)
      segment = segment.next

    check(list.len == flattened.len)

    # check the iterator
    var index = 0
    for actual in list.asc:
      let expected = flattened[index]
      check(actual.value == expected)
      index += 1

    # check the reverse pairs iterator
    index = 0
    for actual in list.desc:
      let expected = flattened[flattened.len - index - 1]
      check(actual.value == expected)
      index += 1

    # check the head and the tail
    if flattened.len != 0:
      check(list.head.items[0].value == flattened[0])
      check(list.tail.items[list.tail.items.len - 1].value == flattened[flattened.len - 1])

  test "empty":
    let list = newNunroll(getter, 4)
    checkList(list, @[])

  test "stores id, sort and value":
    let list = newNunroll(getter, 4)
    list.add(5)
    for item in list.asc:
      check(item.id == 10)
      check(item.sort == 20)
      check(item.value == 5)

  test "add":
    let list = newNunroll(getter, 4)
    list.add(2)
    checkList(list, @[2])
    list.add(1)
    checkList(list, @[1, 2])
    list.add(6); list.add(3); list.add(8);
    checkList(list, @[1, 2, 3, 6], @[8])

  test "add will add duplicates":
    let list = newNunroll(getter, 4)
    list.add(2); list.add(2); list.add(2)
    checkList(list, @[2, 2, 2])

    list.add(3); list.add(3); list.add(2)
    checkList(list, @[2, 2, 2], @[2, 3, 3])

    list.add(1); list.add(5)
    checkList(list, @[1, 2, 2, 2], @[2, 3, 3, 5])

  test "add reverse":
    let list = newNunroll(getter, 4)
    for i in countdown(9, 0): list.add(i)
    checkList(list, @[0, 1], @[2, 3, 4, 5], @[6, 7, 8, 9])

  test "randomness":
    for i in 0..<1_000:
      let list = newNunroll(getter, math.random(4) + 4)
      for i in 0..<math.random(1_000):
        list.add(math.random(100_000))

      var prev = 0
      for item in list.asc:
        check(item.sort >= prev)
        prev = item.sort

  test "delete empty":
    let list = newNunroll(getter, 4)
    check(list.delete(5) == false)
    checkList(list, @[])

  test "delete miss":
    let list = newNunroll(getter, 4)
    list.add(4)
    check(list.delete(5) == false)
    checkList(list, @[4])

    list.add(6)
    check(list.delete(5) == false)
    checkList(list, @[4, 6])

  test "delete when 1":
    let list = newNunroll(getter, 4)
    list.add(4)
    check(list.delete(4) == true)
    checkList(list, @[])

  test "delete when 2":
    let list = newNunroll(getter, 4)
    list.add(4); list.add(6)
    check(list.delete(4) == true)
    checkList(list, @[6])

    check(list.delete(6) == true)
    checkList(list, @[])

  test "delete from multiple segments":
    let list = newNunroll(getter, 4)
    for i in 1..10: list.add(i)

    check(list.delete(0) == false)
    checkList(list, @[1, 2, 3, 4], @[5, 6, 7, 8], @[9, 10])

    list.delete(4)
    checkList(list, @[1, 2, 3], @[5, 6, 7, 8], @[9, 10])

    list.delete(5); list.delete(6)
    checkList(list, @[1, 2, 3], @[7, 8, 9, 10])
