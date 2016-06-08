# Finding an item (used for updates and deletes) involves first finding the first
# possible segment based on the item's sort, then iterating over adjacent segments
# for the specific item. This dual-stage approach is [usually] more efficient since
# finding a segment is O(N/M) where N is the total number of elements and M is the
# segment density. However, values with low cardinality might have the same sort
# value spread across multiple adjacent segments. Therefore, we must also scan the
# found segment's siblings until either the item is found (by id) or the sort changes.
# If the sort changes, the item isn't in the list.
type
  Relative = enum
    Before, After, Self

  Segment*[V] = ref object
    prev*: Segment[V]
    next*: Segment[V]
    items*: seq[V]

  List*[V] = ref object
    count: int
    density: int
    head*: Segment[V]
    tail*: Segment[V]
    comparer: proc(left, right: V): int {.nimcall, noSideEffect.}

proc newSegment[V](density: int): Segment[V] =
  new(result)
  result.items = newSeq[V](density)
  result.items.setLen(0)

proc newSegment[V](item: V, density: int): Segment[V] =
  new(result)
  result.items = newSeq[V](density)
  result.items[0] = item
  result.items.setLen(1)

proc first[V](segment: Segment[V]): V {.inline, noSideEffect.} =
  return segment.items[0]

proc last[V](segment: Segment[V]): V {.inline, noSideEffect.} =
  return segment.items[segment.items.len - 1]

proc add[V](segment: Segment[V], item: V, comparer: proc(left, right: V): int {.nimcall, noSideEffect.}) =
  let length = segment.items.len
  var insertIndex = length
  for i in 0..<length:
    let existing = segment.items[i]
    if comparer(existing, item) == 1:
      insertIndex = i
      break

  # add an extra item at the end of our list
  segment.items.add(item)

  # shift everything to the right
  for i in countdown(length, insertIndex+1):
    segment.items[i] = segment.items[i-1]

  segment.items[insertIndex] = item

# The List has reason to tell us to add this item to the end of our items
# We trust it (it's probably trying to compact the segments a little)
proc append[V](segment: Segment[V], item: V) =
  segment.items.add(item)

# The List has reason to tell us to add this item to the front of our items
# We trust it (it's probably trying to compact the segments a little)
proc prepend[V](segment: Segment[V], item: V) =
  segment.items.add(item) # grow the list by 1
  for i in countdown(segment.items.len-2, 0):  # shift everything to the right
    segment.items[i+1] = segment.items[i]
  segment.items[0] = item

# An optimized function used when compacting. By the time this is called, our
# min value has already been moved to the previous segment. Our job is two-fold:
# 1 - Remove the min
# 2 - Add the new item (which might go anywhere in the segment)
# Since we know both these things have to happen, we can be more efficient than
# doing an individual pop + add
proc firstSwap[V](segment: Segment[V], item: V, comparer: proc(left, right: V): int {.nimcall, noSideEffect.}) =
  for i in 1..<segment.items.len:
    let existing = segment.items[i]
    if comparer(existing, item) == -1:
      segment.items[i-1] = existing
    else:
      segment.items[i-1] = item
      return
  segment.items[segment.items.len-1] = item

# delete the element at the specific index
proc del[V](segment: Segment[V], idx: int) =
  assert(idx >= 0, "delete negative segment idx")

  for i in idx+1..<segment.items.len:
    segment.items[i-1] = segment.items[i]

  segment.items.setLen(segment.items.len - 1)

# return how much freespace a segment has
proc freeSpace[V](list: List[V], segment: Segment[V]): int {.inline.} =
  if segment.isNil: return 0
  return list.density - segment.items.len

# merge one segment into another:
proc merge[V](list: List[V], smaller: Segment[V], larger: Segment[V]) =
  for item in larger.items:
    smaller.items.add(item)

  smaller.next = larger.next
  if not smaller.next.isNil:
    smaller.next.prev = smaller
  else:
    list.tail = smaller

# removes an empty segment
proc remove[V](list: List[V], segment: Segment[V]) =
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
proc findSegment[V](list: List[V], item: V): tuple[segment: Segment[V], rel: Relative] {.noSideEffect.} =
  let head = list.head
  let tail = list.tail

  # short circuit for new biggest sort (insert ascending)
  if list.comparer(item, tail.last) == 1:
    if list.freeSpace(tail) > 0: return (tail, Self)
    return (tail, After)

  # short circuit for new smallest sort (insert descending)
  if list.comparer(item, head.first) == -1:
    if list.freeSpace(head) > 0: return (head, Self)
    return (head, Before)

  if list.comparer(item, head.last) == -1:
    return (head, Self)

  var segment = tail
  while not segment.isNil:
    if list.comparer(item, segment.first) != -1:
      return (segment, Self)
    segment = segment.prev

  assert(false, "failed to find index")

# Finds the index of a specific item (by id). This should be called after findSegment
# to find the initial segment to start searching. It should only be called when findSegment
# return rel == Self. In all other cases, the specific item is not in the list and this
# procedure should not be called.
proc index[V](list: List[V], start: Segment[V], item: V): tuple[segment: Segment[V], idx: int] =
  var segment = start
  while not segment.isNil and list.comparer(item, segment.last) != 1:
    for i in 0..<segment.items.len:
      if segment.items[i] == item: return (segment, i)
    segment = segment.prev

  return (nil, -1)

# a new values needs to be inserted in a full segment. Split the segment, and figure
# out which of the two new segments should get the value
#
# Reuse the segment to keep the "bottom" part of the list.
proc split[V](list: List[V], segment: Segment[V], item: V) =
  let top = newSegment[V](list.density)
  let cutoff = int(segment.items.len / 2)

  # copy the top part of the segment to the new segment
  for i in cutoff..<segment.items.len:
    top.items.add(segment.items[i])

  # resize the bottom part
  segment.items.setLen(cutoff)

  if list.comparer(top.first, item) == -1:
    top.add(item, list.comparer)
  else:
    segment.add(item, list.comparer)

  top.next = segment.next
  top.prev = segment
  segment.next = top

  if top.next.isNil:
    list.tail = top
  else:
    top.next.prev = top

proc newNunroll*[V](comparer: proc(left, right: V): int {.nimcall, noSideEffect.}, density: int = 64): List[V] =
  result = List[V](
    density: density,
    comparer: comparer,
  )

proc del*[V](list: List[V], item: V): bool {.discardable.} =
  if list.head.isNil: return false

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

proc clear*[V](list: List[V]) {.inline.} =
  list.head = nil
  list.tail = nil
  list.count = 0

# Adds or updates the value. If oldValue is nil, it is assumed that newValue represents
# a distinctly new item. If oldValue is not nil, additional checks are made to
# ensure no duplicate is set.
proc update*[V](list: List[V], newValue: V, oldValue: V) =
  let density = list.density

  # optimized for when the value has changed, but not its sort
  if not oldValue.isNil:
    assert(oldValue == newValue, "update oldValue should have same id as newValue")

    if list.comparer(oldValue, newValue) == 0:
      let found = list.findSegment(newValue)
      let oldIndex = list.index(found.segment, oldValue)
      if not oldIndex.segment.isNil:
        # sort hasn't changed, can just overwrite existing one
        oldIndex.segment.items[oldIndex.idx] = newValue
        return
    else:
      list.del(oldValue)

  if list.head.isNil:
    let segment = newSegment(newValue, density)
    list.head = segment
    list.tail = segment
    list.count = 1
    return

  let found = list.findSegment(newValue)
  let target = found.segment

  list.count += 1
  # Value belongs in a specific segment
  if found.rel == Self:
    if list.freeSpace(target) > 0:
      target.add(newValue, list.comparer)
    else:
      list.split(target, newValue)
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
    target.firstSwap(newValue, list.comparer)
    return

  # Does our next have space? If so, move the target's max value there.
  # - We append the target's max to the next segment
  # - We set shrink the target's length by 1
  # - We add the new item
  if not target.next.isNil and list.freespace(target.next) > 0:
    let last = target.items[target.items.len - 1]
    target.next.prepend(last)
    target.items.setLen(target.items.len - 1)
    target.add(newValue, list.comparer)
    return

  let segment = newSegment(newValue, list.density)
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

proc add*[V](list: List[V], newValue: V) {.inline.} =
  list.update(newValue, nil)

proc len*[V](list: List[V]): int {.inline, noSideEffect.} = list.count

iterator asc*[V](list: List[V]): V {.inline, noSideEffect.} =
  var segment = list.head
  while not segment.isNil:
    for i in countup(0, <segment.items.len): yield segment.items[i]
    segment = segment.next

iterator desc*[V](list: List[V]): V {.noSideEffect.} =
  var segment = list.tail
  while not segment.isNil:
    for i in countdown(<segment.items.len, 0): yield segment.items[i]
    segment = segment.prev
