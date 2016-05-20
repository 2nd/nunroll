# A Sorted Unrolled Link List for nim

An unrolled linked list is a blend between a dynamic array and a link list. Visualize a linked list where every node is an array of values (rather than an individual value). Each node can hold up to X values, called the `density`.

An unrolled list lists is an ideal data structure for read-heavy indexing. The use of arrays minimizes cache misses. The use of linked lists makes it sufficient for a moderate volume of modification (inserts, updates and deletes).

## Usage
```nim
let sort = proc(u: User): int = u.age

# create a Nunroll of type [int, User]
# where the int is the sort type
var list = newNunroll(sort)
list.add(user1)
list.add(user2)
list.add(user3)

# get users
for user in list: ...

# get users with an increment counter ('cuz)
for i, user in list: ...

# get users with sorted value (age, in this case)
for age, user in list.ranked: ...

# get users in reverse order
for user in list.ritems: ...

# get users with an increment counter ('cuz) in reverse order
for i, user in list.rpairs: ...

# get users with sorted value (age, in this case) in reverse order
for age, user in list.rranked: ...
```

## Todo
Thread-safety
Updates
Deletes
