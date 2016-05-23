type
  Relative = enum
    Before, After, Self

  Item*[I, S, V] = tuple[
    id: I,
    sort: S,
    value: V,
  ]

  Getter*[I, S, V] = proc(v: V): Item[I, S, V] {.noSideEffect.}

  Segment*[I, S, V] = ref object
    prev*: Segment[I, S, V]
    next*: Segment[I, S, V]
    items*: seq[Item[I, S, V]]

  List*[I, S, V] = ref object
    count: int
    density: int
    head*: Segment[I, S, V]
    tail*: Segment[I, S, V]
    getter: Getter[I, S, V]

proc newSegment[I, S, V](density: int): Segment[I, S, V] =
  new(result)
  result.items = newSeq[Item[I, S, V]](density)
  result.items.setLen(0)

proc newSegment[I, S, V](item: Item[I, S, V], density: int): Segment[I, S, V] =
  new(result)
  result.items = newSeq[Item[I, S, V]](density)
  result.items[0] = item
  result.items.setLen(1)

proc min[I, S, V](segment: Segment[I, S, V]): S {.inline, noSideEffect.} =
  return segment.items[0].sort

proc max[I, S, V](segment: Segment[I, S, V]): S {.inline, noSideEffect.} =
  return segment.items[segment.items.len - 1].sort

proc index[I, S, V](segment: Segment[I, S, V], id: I): int {.inline, noSideEffect.} =
  for i in 0..<segment.items.len:
    if segment.items[i].id == id:
      return i
  return -1

proc add[I, S, V](segment: Segment[I, S, V], item: Item[I, S, V]) =
  var insertIndex = segment.items.len
  for i in 0..<segment.items.len:
    let existing = segment.items[i]
    if existing.sort > item.sort:
      insertIndex = i
      break

  # add an extra item at the end of our list
  segment.items.add(item)

  # shift everything to the right
  for i in countdown(segment.items.len-1, insertIndex+1):
    segment.items[i] = segment.items[i-1]

  segment.items[insertIndex] = item

# The List has reason to tell us to add this item to the end of our items
# We trust it (it's probably trying to compact the segments a little)
proc append[I, S, V](segment: Segment[I, S, V], item: Item[I, S, V]) =
  segment.items.add(item)

# The List has reason to tell us to add this item to the front of our items
# We trust it (it's probably trying to compact the segments a little)
proc prepend[I, S, V](segment: Segment[I, S, V], item: Item[I, S, V]) =
  segment.items.add(item) # grow the list by 1
  for i in countdown(segment.items.len-2, 0):  # shift everything to the right
    segment.items[i+1] =segment.items[i]
  segment.items[0] = item

# An optimized function used when compacting. By the time this is called, our
# min value has already been moved to the previous segment. Our job is two-fold:
# 1 - Remove the min
# 2 - Add the new item (which might go anywhere in the segment)
# Since we know both these things have to happen, we can be more efficient than
# doing an individual pop + add
proc firstSwap[I, S, V](segment: Segment[I, S, V], item: Item[I, S, V]) =
  for i in 1..<segment.items.len:
    let existing = segment.items[i]
    if existing.sort < item.sort:
      segment.items[i-1] = existing
    else:
      segment.items[i-1] = item
      return
  segment.items[segment.items.len-1] = item

# delete the element at the specific index
proc del[I, S, V](segment: Segment[I, S, V], idx: int) =
  assert(idx >= 0, "delete negative segment idx")

  for i in idx+1..<segment.items.len:
    segment.items[i-1] = segment.items[i]

  segment.items.setLen(segment.items.len - 1)

# return how much freespace a segment has
proc freeSpace[I, S, V](list: List[I, S, V], segment: Segment[I, S, V]): int {.inline.} =
  if segment.isNil: return 0
  return list.density - segment.items.len

# merge one segment into another:
proc merge[I, S, V](list: List[I, S, V], smaller: Segment[I, S, V], larger: Segment[I, S, V]) =
  for item in larger.items:
    smaller.items.add(item)

  smaller.next = larger.next
  if not smaller.next.isNil:
    smaller.next.prev = smaller
  else:
    list.tail = smaller

# removes an empty segment
proc remove[I, S, V](list: List[I, S, V], segment: Segment[I, S, V]) =
  assert(segment.items.len == 0, "removing non-empty segment")
  if not segment.next.isNil:
    segment.next.prev = segment.prev
  else:
    list.tail = segment.prev

  if not segment.prev.isNil:
    segment.prev.next = segment.next
  else:
    list.head = segment.next

# Find which segment a sort value belongs to.
# When the sort belongs within an existing segment, the segment is returned
# along with a Self value
# When the sort belongs to a segment which does not exist, rel will either be
# Before, After or None. Before and After indicate that a new segment should
# be created either before or after the provided segment. None means the list
# is empty and a new segment needs to be added to the head&tail
proc findSegment[I, S, V](list: List[I, S, V], item: Item[I, S, V]): tuple[segment: Segment[I, S, V], rel: Relative] {.noSideEffect.} =
  let sort = item.sort
  let head = list.head
  let tail = list.tail

  # short circuit for new biggest sort (insert ascending)
  if sort > tail.max:
    if list.freeSpace(tail) > 0: return (tail, Self)
    return (tail, After)

  # short circuit for new smallest sort (insert descending)
  if sort < head.min:
    if list.freeSpace(head) > 0: return (head, Self)
    return (head, Before)

  if sort < head.max:
    return (head, Self)

  var segment = tail
  while not segment.isNil:
    if sort >= segment.min:
      return (segment, Self)
    segment = segment.prev

  assert(false, "failed to find index")

# Finds the index of a specific item (by id). This should be called after findSegment
# to find the initial segment to start searching. It should only be called when findSegment
# return rel == Self. In all other cases, the specific item is not in the list and this
# procedure should not be called.
proc index[I, S, V](list: List[I, S, V], start: Segment[I, S, V], item: Item[I, S, V]): tuple[segment: Segment[I, S, V], idx: int] =
  let id = item.id
  let sort = item.sort

  var segment = start
  while not segment.isNil and sort >= segment.min:
    for i in 0..<segment.items.len:
      if segment.items[i].id == id: return (segment, i)
    segment = segment.prev

  return (nil, -1)

# a new values needs to be inserted in a full segment. Split the segment, and figure
# out which of the two new segments should get the value
#
# Reuse the segment to keep the "bottom" part of the list.
proc split[I, S, V](list: List[I, S, V], segment: Segment[I, S, V], item: Item[I, S, V]) =
  let top = newSegment[I, S, V](list.density)
  let cutoff = int(segment.items.len / 2)

  # copy the top part of the segment to the new segment
  for i in cutoff..<segment.items.len:
    top.items.add(segment.items[i])

  # resize the bottom part
  segment.items.setLen(cutoff)

  if top.min < item.sort:
    top.add(item)
  else:
    segment.add(item)

  top.next = segment.next
  top.prev = segment
  segment.next = top

  if top.next.isNil:
    list.tail = top
  else:
    top.next.prev = top

proc newNunroll*[I, S, V](getter: Getter[I, S, V], density: int = 64): List[I, S, V] =
  result = List[I, S, V](
    getter: getter,
    density: density
  )

proc del[I, S, V](list: List[I, S, V], item: Item[I, S, V]): bool {.discardable.} =
  let found = list.findSegment(item)
  if found.rel != Self: return false

  let index = list.index(found.segment, item)
  if index.segment.isNil: return false

  let segment = index.segment
  segment.del(index.idx)
  list.count -= 1

  # can we merge the segment with a neighbour?
  let length = segment.items.len
  if length == 0:
    list.remove(segment)
  elif list.freeSpace(segment.prev) >= length:
    list.merge(segment.prev, segment)
  elif list.freeSpace(segment.next) >= length:
    list.merge(segment, segment.next)

  return true

proc add*[I, S, V](list: List[I, S, V], newValue: V) {.inline.} =
  list.update(newValue, nil)

# Adds or updates the value. If oldValue is nil, it is assumed that newValue represents
# a distinctly new item. If oldValue is not nil, additional checks are made to
# ensure no duplicate is set.
proc update*[I, S, V](list: List[I, S, V], newValue: V, oldValue: V) =
  let density = list.density
  let item = list.getter(newValue)

  # optimized for when the value has changed, but not its sort
  if not oldValue.isNil:
    let oldItem = list.getter(oldValue)
    assert(oldItem.id == item.id, "update oldValue should have same id as newValue")

    if oldItem.sort == item.sort:
      let found = list.findSegment(item)
      let oldIndex = list.index(found.segment, oldItem)
      if not oldIndex.segment.isNil:
        # sort hasn't changed, can just overwrite existing one
        oldIndex.segment.items[oldIndex.idx] = item
        return
    else:
      list.del(oldItem)

  if list.head.isNil:
    let segment = newSegment(item, density)
    list.head = segment
    list.tail = segment
    list.count = 1
    return

  let found = list.findSegment(item)
  let target = found.segment

  list.count += 1
  # Value belongs in a specific segment
  if found.rel == Self:
    if list.freeSpace(target) > 0:
      target.add(item)
    else:
      list.split(target, item)
    return

  # We *think* we need to create a new segment relative to X.
  # Before we take such a drastc step, let's see if we can free some in X by
  # moving an item to its next or prev segment

  # Does our prev have space? If so, move target's min value there.
  # - We append the target's min to the previous segment
  # - We call the specialized firstSwap to remove the first item and add the new item
  if not target.prev.isNil and list.freeSpace(target.prev) > 0:
    let first = target.items[0]
    target.prev.append(first)
    target.firstSwap(item)
    return

  # Does our next have space? If so, move the target's max value there.
  # - We append the target's max to the next segment
  # - We set shrink the target's length by 1
  # - We add the new item
  if not target.next.isNil and list.freespace(target.next) > 0:
    let last = target.items[target.items.len - 1]
    target.next.prepend(last)
    target.items.setLen(target.items.len - 1)
    target.add(item)
    return

  let segment = newSegment(item, list.density)
  if found.rel == Before:
    segment.next = target
    segment.prev = target.prev
    target.prev = segment

    if segment.prev.isNil:
      list.head = segment
    else:
      segment.prev.next = segment

  else: # after
    segment.prev = target
    segment.next = target.next
    target.next = segment

    if segment.next.isNil:
      list.tail = segment
    else:
      segment.next.prev = segment

proc del*[I, S, V](list: List[I, S, V], value: V): bool {.discardable.} =
  if list.head.isNil: return false
  list.del(list.getter(value))

proc len*[I, S, V](list: List[I, S, V]): int {.inline, noSideEffect.} = list.count

iterator asc*[I, S, V](list: List[I, S, V]): Item[I, S, V] {.inline, noSideEffect.} =
  var segment = list.head
  while not segment.isNil:
    for i in countup(0, <segment.items.len): yield segment.items[i]
    segment = segment.next

iterator desc*[I, S, V](list: List[I, S, V]): Item[I, S, V] {.noSideEffect.} =
  var segment = list.tail
  while not segment.isNil:
    for i in countdown(<segment.items.len, 0): yield segment.items[i]
    segment = segment.prev
