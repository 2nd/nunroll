import unittest, nunroll, math, times, tables, sequtils

# fake object
type User = ref object
  id: int
  createdAt: int

proc userInfo(user: User): nunroll.Item[int, int, User] {.noSideEffect.} =
  return (id: user.id, sort: user.createdAt, value: user)

proc newUser(id: int, createdAt: int = -1): User =
  new(result)
  result.id = id
  result.createdAt = if createdAt == -1: id * 4 else: createdAt

proc `$`(user: User): string =
  if user.isNil: return "nil"
  else: return "id: " & $user.id & ", sort: " & $user.createdAt

proc debug[I, S, V](list: List[I, S, V]) =
  echo ""
  var node = list.head
  while not node.isNil:
    echo node.items.map(proc(item: Item[int, int, User]): int = item.id)
    node = node.next

suite "nunroll":

  let seed = int(times.cpuTime() * 10000000)
  echo "random seed ", seed
  math.randomize(seed)

  # checks both the exposed iterator values (items and pair)
  # as well as the internal segment structure to make sure
  # the layout is what it should be
  proc checkList(list: nunroll.List[int, int, User], all: varargs[seq[int]]) =
    # first, check the segment structure
    var segment = list.head
    var flattened = newSeq[int]()
    for expected in all:
      for i, e in expected:
        check(segment.items[i].id == e)
        flattened.add(e)
      segment = segment.next

    check(list.len == flattened.len)

    # check the iterator
    var index = 0
    for actual in list.asc:
      let expected = flattened[index]
      check(actual.id == expected)
      index += 1

    # check the reverse pairs iterator
    index = 0
    for actual in list.desc:
      let expected = flattened[flattened.len - index - 1]
      check(actual.id == expected)
      index += 1

    # check the head and the tail
    if flattened.len != 0:
      check(list.head.items[0].id == flattened[0])
      check(list.tail.items[list.tail.items.len - 1].id == flattened[flattened.len - 1])

  test "empty":
    let list = newNunroll(userInfo, 4)
    checkList(list, @[])

  test "stores id, sort and value":
    let list = newNunroll(userInfo, 4)
    list.add(newUser(5))
    for item in list.asc:
      check(item.id == 5)
      check(item.sort == 20)
      check(item.value.id == 5)

  test "add":
    let list = newNunroll(userInfo, 4)
    list.add(newUser(2))
    checkList(list, @[2])
    list.add(newUser(1))
    checkList(list, @[1, 2])
    list.add(newUser(6)); list.add(newUser(3)); list.add(newUser(8));
    checkList(list, @[1, 2, 3, 6], @[8])

  test "add will add duplicates":
    let list = newNunroll(userInfo, 4)
    list.add(newUser(2)); list.add(newUser(2)); list.add(newUser(2))
    checkList(list, @[2, 2, 2])

    list.add(newUser(3)); list.add(newUser(3)); list.add(newUser(2))
    checkList(list, @[2, 2], @[2, 2, 3, 3])

    list.add(newUser(1)); list.add(newUser(5))
    checkList(list, @[1, 2, 2, 2], @[2, 3, 3, 5])

  test "add reverse":
    let list = newNunroll(userInfo, 4)
    for i in countdown(9, 0): list.add(newUser(i))
    checkList(list, @[0, 1], @[2, 3, 4, 5], @[6, 7, 8, 9])

  test "delete empty":
    let list = newNunroll(userInfo, 4)
    check(list.del(newUser(5)) == false)
    checkList(list, @[])

  test "delete miss":
    let list = newNunroll(userInfo, 4)
    list.add(newUser(4))
    check(list.del(newUser(5)) == false)
    checkList(list, @[4])

    list.add(newUser(6))
    check(list.del(newUser(5)) == false)
    checkList(list, @[4, 6])

  test "delete when 1":
    let list = newNunroll(userInfo, 4)
    list.add(newUser(4))
    check(list.del(newUser(4)) == true)
    checkList(list, @[])

  test "delete when 2":
    let list = newNunroll(userInfo, 4)
    list.add(newUser(4)); list.add(newUser(6))
    check(list.del(newUser(4)) == true)
    checkList(list, @[6])

    check(list.del(newUser(6)) == true)
    checkList(list, @[])

  test "delete from multiple segments":
    let list = newNunroll(userInfo, 4)
    for i in 1..10: list.add(newUser(i))

    check(list.del(newUser(0)) == false)
    checkList(list, @[1, 2, 3, 4], @[5, 6, 7, 8], @[9, 10])

    list.del(newUser(4))
    checkList(list, @[1, 2, 3], @[5, 6, 7, 8], @[9, 10])

    list.del(newUser(5)); list.del(newUser(6))
    checkList(list, @[1, 2, 3], @[7, 8, 9, 10])

  test "randomized":
    for i in 0..<1_000:
      var master = initTable[int, User]()
      let list = newNunroll(userInfo, math.random(64) + 32)

      for j in 0..<math.random(500)+100:
        if j mod 6 == 0:
          for id, user in master:
            check(list.del(user) == true)
            master.del(id)
            break
          continue
        let user = newUser(math.random(10_000), math.random(10_000))
        list.update(user, master.getOrDefault(user.id))
        master[user.id] = user

      check(list.len == master.len)

      var prev = 0
      for item in list.asc:
        check(master.contains(item.id))
        check(item.sort >= prev)
        prev = item.sort
