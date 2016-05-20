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

proc len[I, S, V](segment: Segment[I, S, V]): int {.inline, noSideEffect.} =
  return segment.items.len

proc min[I, S, V](segment: Segment[I, S, V]): S {.inline, noSideEffect.} =
  return segment.items[0].sort

proc max[I, S, V](segment: Segment[I, S, V]): S {.inline, noSideEffect.} =
  return segment.items[segment.len - 1].sort

proc hasSpace[I, S, V](segment: Segment[I, S, V], density: int): bool {.inline, noSideEffect.} =
  return segment.len < density

proc add[I, S, V](segment: Segment[I, S, V], item: Item[I, S, V]) =
  var insertIndex = segment.len
  for i, existing in segment.items:
    if existing.sort > item.sort:
      insertIndex = i
      break

  # add an extra item at the end of our list
  segment.items.add(item)

  # shift everything to the right
  for i in countdown(segment.len-1, insertIndex+1):
    segment.items[i] = segment.items[i-1]

  segment.items[insertIndex] = item

# Find which segment a sort value belongs to
# When the sort belongs within an existing segment, the segment is returned
# along with a Self value
# When the sort belongs to a segment which does not exist, rel will either be
# Before, After or None. Before and After indicate that a new segment should
# be created either before or after the provided segment. None means the list
# is empty and a new segment needs to be added to the head&tail
proc findSegment[I, S, V](list: List[I, S, V], sort: S): tuple[segment: Segment[I, S, V], rel: Relative] {.noSideEffect.} =
  var segment = list.tail
  if segment.isNil: return (nil, None)

  if sort > segment.max:
    if segment.hasSpace(list.density): return (segment, Self)
    return (segment, After)

  while not segment.isNil:
    if sort > segment.min:
      return (segment, Self)
    if segment.prev.isNil and segment.hasSpace(list.density):
      return (segment, Self)

    segment = segment.prev

  return (list.head, Before)

# a new values needs to be inserted in a full node. Split the node, and figure
# out which of the two new segments should get the value
#
# Reuse the segment to keep the "bottom" part of the list.

proc split[I, S, V](list: List[I, S, V], segment: Segment[I, S, V], item: Item[I, S, V]) =
  let top = newSegment[I, S, V](list.density)
  let cutoff = int(segment.len / 2)

  # copy the top part of the segment to the new segment
  for i in cutoff..<segment.len:
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

proc add*[I, S, V](list: List[I, S, V], value: V) =
  let item = list.getter(value)

  let found = list.findSegment(item.sort)
  list.count += 1

  if found.rel == Self:
    if found.segment.hasSpace(list.density):
      found.segment.add(item)
    else:
      list.split(found.segment, item)
    return

  let segment = newSegment(item, list.density)
  case found.rel:
    of Before:
      segment.next = found.segment
      segment.prev = found.segment.prev
      found.segment.prev = segment

      if segment.prev.isNil:
        list.head = segment
      else:
        segment.prev.next = segment

    of After:
      segment.prev = found.segment
      segment.next = found.segment.next
      found.segment.next = segment

      if segment.next.isNil:
        list.tail = segment
      else:
        segment.next.prev = segment

    else:
      list.head = segment
      list.tail = segment

proc len*[I, S, V](list: List[I, S, V]): int {.inline, noSideEffect.} = list.count

iterator asc*[I, S, V](list: List[I, S, V]): Item[I, S, V] {.inline, noSideEffect.} =
  var segment = list.head
  while not segment.isNil:
    for i in countup(0, <segment.len): yield segment.items[i]
    segment = segment.next

iterator desc*[I, S, V](list: List[I, S, V]): Item[I, S, V] {.noSideEffect.} =
  var segment = list.tail
  while not segment.isNil:
    for i in countdown(<segment.len, 0): yield segment.items[i]
    segment = segment.prev
