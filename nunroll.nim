type
  Relative = enum
    None, Before, After, Self

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

proc `[]`[I, S, V](segment: Segment[I, S, V], i: int): Item[I, S, V] {.inline, noSideEffect.} =
  return segment.items[i]

proc `[]=`[I, S, V](segment: Segment[I, S, V], i: int, item: Item[I, S, V]) {.inline, noSideEffect.} =
  segment.items[i] = item

proc len[I, S, V](segment: Segment[I, S, V]): int {.inline, noSideEffect.} =
  return segment.items.len

proc min[I, S, V](segment: Segment[I, S, V]): S {.inline, noSideEffect.} =
  return segment[0].sort

proc max[I, S, V](segment: Segment[I, S, V]): S {.inline, noSideEffect.} =
  return segment[segment.len - 1].sort

proc hasSpace[I, S, V](segment: Segment[I, S, V], density: int): bool {.inline, noSideEffect.} =
  return segment.len < density

proc index[I, S, V](segment: Segment[I, S, V], id: I): int {.inline, noSideEffect.} =
  for i in 0..<segment.len:
    if segment[i].id == id:
      return i
  return -1

proc add[I, S, V](segment: Segment[I, S, V], item: Item[I, S, V]) =
  var insertIndex = segment.len
  for i in 0..<segment.len:
    let existing = segment[i]
    if existing.sort > item.sort:
      insertIndex = i
      break

  # add an extra item at the end of our list
  segment.items.add(item)

  # shift everything to the right
  for i in countdown(segment.len-1, insertIndex+1):
    segment[i] = segment[i-1]

  segment[insertIndex] = item

# The List has reason to tell us to add this item to the end of our items
# We trust it (it's probably trying to compact the segments a little)
proc append[I, S, V](segment: Segment[I, S, V], item: Item[I, S, V]) =
  segment.items.add(item)

# The List has reason to tell us to add this item to the front of our items
# We trust it (it's probably trying to compact the segments a little)
proc prepend[I, S, V](segment: Segment[I, S, V], item: Item[I, S, V]) =
  segment.items.add(item) # grow the list by 1
  for i in countdown(segment.len-2, 0):  # shift everything to the right
    segment[i+1] =segment[i]
  segment[0] = item

# An optimized function used when compacting. By the time this is called, our
# min value has already been moved to the previous segment. Our job is two-fold:
# 1 - Remove the min
# 2 - Add the new item (which might go anywhere in the segment)
# Since we know both these things have to happen, we can be more efficient than
# doing an individual pop + add
proc firstSwap[I, S, V](segment: Segment[I, S, V], item: Item[I, S, V]) =
  for i in 1..<segment.len:
    let existing = segment[i]
    if existing.sort < item.sort:
      segment[i-1] = existing
    else:
      segment[i-1] = item
      return

# Find which segment a sort value belongs to
# When the sort belongs within an existing segment, the segment is returned
# along with a Self value
# When the sort belongs to a segment which does not exist, rel will either be
# Before, After or None. Before and After indicate that a new segment should
# be created either before or after the provided segment. None means the list
# is empty and a new segment needs to be added to the head&tail
proc index*[I, S, V](list: List[I, S, V], item: Item[I, S, V]): tuple[segment: Segment[I, S, V], idx: int, rel: Relative] {.noSideEffect.} =
  let sort = item.sort
  let head = list.head
  let tail = list.tail

  # if we have no segements, this is the first item, that's easy.
  if head.isNil: return (nil, -1, None)

  # short circuit for new biggest sort (insert ascending)
  if sort > tail.max:
    if tail.hasSpace(list.density): return (tail, -1, Self)
    return (tail, -1, After)

  # short circuit for new smallest sort (insert descending)
  if sort < head.min:
    if head.hasSpace(list.density): return (head, -1, Self)
    return (head, -1, Before)

  if sort <= head.max:
    return (head, head.index(item.id), Self)

  var segment = tail
  while not segment.isNil:
    if sort >= segment.min:
      return (segment, segment.index(item.id), Self)
    segment = segment.prev

  assert(false, "failed to find index")

# a new values needs to be inserted in a full node. Split the node, and figure
# out which of the two new segments should get the value
#
# Reuse the segment to keep the "bottom" part of the list.

proc split[I, S, V](list: List[I, S, V], segment: Segment[I, S, V], item: Item[I, S, V]) =
  let top = newSegment[I, S, V](list.density)
  let cutoff = int(segment.len / 2)

  # copy the top part of the segment to the new segment
  for i in cutoff..<segment.len:
    top.items.add(segment[i])

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

proc add*[I, S, V](list: List[I, S, V], value: V) =
  let density = list.density
  let item = list.getter(value)
  let found = list.index(item)
  let target = found.segment

  list.count += 1

  # the first segment
  if target.isNil:
    let segment = newSegment(item, density)
    list.head = segment
    list.tail = segment
    return

  # Value belongs in a specific segment
  if found.rel == Self:
    if target.hasSpace(density):
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
  if not target.prev.isNil and target.prev.hasSpace(density):
    let first = target.items[0]
    target.prev.append(first)
    target.firstSwap(item)
    return

  # Does our next have space? If so, move the target's max value there.
  # - We append the target's max to the next segment
  # - We set shrink the target's length by 1
  # - We add the new item
  if not target.next.isNil and target.next.hasSpace(density):
    let last = target.items[target.len - 1]
    target.next.prepend(last)
    target.items.setLen(target.len - 1)
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

# proc delete*[I, S, V](list: List[I, S, V], id: I): bool =
#
# proc delete*[I, S, V](list: List[I, S, V], id: I): bool {.inline.} =
#   list.delete(list.getter(value).id)

proc len*[I, S, V](list: List[I, S, V]): int {.inline, noSideEffect.} = list.count

iterator asc*[I, S, V](list: List[I, S, V]): Item[I, S, V] {.inline, noSideEffect.} =
  var segment = list.head
  while not segment.isNil:
    for i in countup(0, <segment.len): yield segment[i]
    segment = segment.next

iterator desc*[I, S, V](list: List[I, S, V]): Item[I, S, V] {.noSideEffect.} =
  var segment = list.tail
  while not segment.isNil:
    for i in countdown(<segment.len, 0): yield segment[i]
    segment = segment.prev
