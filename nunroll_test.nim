import unittest, nunroll, math, times

suite "nunroll":

  nunroll.MAX_SEGMENT_SIZE = 4

  # checks both the exposed iterator values (items and pair)
  # as well as the internal segment structure to make sure
  # the layout is what it should be
  proc checkIter[S, V](list: nunroll.List[S, V], all: varargs[seq[V]]) =
    # first, check the segment structure
    var segment = list.head
    var flattened = newSeq[V]()
    for expected in all:
      for i, e in expected:
        check(segment.values[i].value == e)
        flattened.add(e)
      segment = segment.next

    check(list.len == flattened.len)

    # check the pairs iterator
    for index, actual in list:
      check(actual == flattened[index])

    # check the items iterator
    var index = 0
    for actual in list:
      check(actual == flattened[index])
      index += 1

    # check the head and the tail
    if flattened.len != 0:
      check(list.head.values[0].value == flattened[0])
      check(list.tail.values[list.tail.values.len - 1].value == flattened[flattened.len - 1])

  test "empty":
    let list = newNunroll(proc(i: int): int = i)
    checkIter(list, @[])

  test "add":
    var list = newNunroll(proc(i: int): int = i)
    list.add(2)
    checkIter(list, @[2])
    list.add(1)
    checkIter(list, @[1, 2])
    list.add(6); list.add(3); list.add(8);
    checkIter(list, @[1, 2, 3, 6], @[8])

  test "add reverse":
    var list = newNunroll(proc(i: int): int = i)
    for i in countdown(9, 0): list.add(i)
    checkIter(list, @[0, 1], @[2, 3, 4, 5], @[6, 7, 8, 9])

  test "randomness":
    let seed = int(times.cpuTime() * 10000000)
    echo "random seed ", seed
    math.randomize(seed)

    for i in 0..<1_000:
      var list = newNunroll(proc(i: int): int = i)
      for i in 0..<math.random(1_000):
        let x = math.random(100_000)
        list.add(x)

      var prev = 0
      for k, value in list:
        check(value >= prev)
        prev = value
