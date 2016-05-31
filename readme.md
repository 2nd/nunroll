# A Sorted Unrolled Link List for nim

An unrolled linked list is a blend between a dynamic array and a link list. Visualize a linked list where every node is an array of values (rather than an individual value). Each node can hold up to X values, called the `density`.

An unrolled list lists is an ideal data structure for read-heavy indexing. The use of arrays minimizes cache misses. The use of linked lists makes it sufficient for a moderate volume of modification (inserts, updates and deletes).

## Usage
```nim
# the compare two values to determine the sort order
proc comparer(left, right: User): int {.noSideEffect.} =
  if left.createdAt < right.createdAt: return -1
  if left.createdAt > right.createdAt: return 1
  return 0

# User must implement `==`, something like:
proc `==`(left, right: User): bool {.inline.} = left.id == right.id

# create a Nunroll of type User (inferred from the comparer)
let list = newNunroll(comparer)
list.add(user1)
list.add(user2)
list.add(user3)

# iterate through users
for user in list.asc:
  echo  item.user

# iterate in reverse:
for user in list.reverse:
  echo user
```

## Todo
Thread-safety
