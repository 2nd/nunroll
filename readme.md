# A Sorted Unrolled Link List for nim

An unrolled linked list is a blend between a dynamic array and a link list. Visualize a linked list where every node is an array of values (rather than an individual value). Each node can hold up to X values, called the `density`.

An unrolled list lists is an ideal data structure for read-heavy indexing. The use of arrays minimizes cache misses. The use of linked lists makes it sufficient for a moderate volume of modification (inserts, updates and deletes).

## Usage
```nim

# create a Nunroll of type [int, User]
# where the int is the sort type
let getter = proc(u: User): nunroll.Item[int, int, User] = (user.id, user.age, user)
var list = newNunroll(getter)
list.add(user1)
list.add(user2)
list.add(user3)

# iterate through users
for user in list: ...
  echo user.id, user.sort, user.value

# iterate in reverse:
for age, user in list.reverse:
  echo user.id, user.sort, user.value
```

## Todo
Thread-safety
Updates
Deletes
