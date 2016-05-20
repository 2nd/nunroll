var DENSITY* = 64

type
  Relative = enum
    None, Before, After, Self

  Value*[S, V] = tuple[
    sort: S,
    value: V
  ]

  Segment*[S, V] = ref object
    prev*: Segment[S, V]
    next*: Segment[S, V]
    values*: seq[Value[S, V]]

  List*[S, V] = object
    count: int
    head*: Segment[S, V]
    tail*: Segment[S, V]
    sort: proc(v: V): S

proc newSegment[S, V](): Segment[S, V] =
  new(result)
  result.values = newSeq[Value[S, V]](DENSITY)
  result.values.setLen(0)

proc newSegment[S, V](value: V, sort: S): Segment[S, V] =
  new(result)
  result.values = newSeq[Value[S, V]](DENSITY)
  result.values[0] = (sort: sort, value: value)
  result.values.setLen(1)

proc len[S, V](segment: Segment[S, V]): int {.inline.} =
  return segment.values.len

proc min[S, V](segment: Segment[S, V]): S {.inline.} =
  return segment.values[0].sort

proc max[S, V](segment: Segment[S, V]): S {.inline.} =
  return segment.values[segment.len - 1].sort

proc hasSpace[S, V](segment: Segment[S, V]): bool {.inline.} =
  return segment.len < DENSITY

proc add[S, V](segment: Segment[S, V], value: V, sort: S) =
  var insertIndex = segment.len
  for i, value in segment.values:
    if value.sort > sort:
      insertIndex = i
      break

  # add an extra item at the end of our list
  let v: Value[S, V] = (sort: sort, value: value)
  segment.values.add(v)

  # shift everything to the right
  for i in countdown(segment.len-1, insertIndex+1):
    segment.values[i] = segment.values[i-1]

  segment.values[insertIndex] = v

# Find which segment a sort value belongs to
# When the sort belongs within an existing segment, the segment is returned
# along with a Relative.Self value
# When the sort belongs to a segment which does not exist, rel will either be
# Before, After or None. Before and After indicate that a new segment should
# be created either before or after the provided segment. None means the list
# is empty and a new segment needs to be added to the head&tail
proc findSegment[S, V](list: List[S, V], sort: S): tuple[segment: Segment[S, V], rel: Relative] =
  var segment = list.tail
  if segment.isNil: return (nil, Relative.None)

  if sort > segment.max:
    if segment.hasSpace: return (segment, Self)
    return (segment, Relative.After)

  while not segment.isNil:
    if sort > segment.min:
      return (segment, Relative.Self)
    if segment.prev.isNil and segment.hasSpace:
      return (segment, Relative.Self)

    segment = segment.prev

  return (list.head, Relative.Before)

# a new values needs to be inserted in a full node. Split the node, and figure
# out which of the two new segments should get the value
#
# Reuse the segment to keep the "bottom" part of the list.

proc split[S, V](list: var List[S, V], segment: Segment[S, V], value: V, sort: S) =
  let top = newSegment[S, V]()
  let cutoff = int(segment.len / 2)

  # copy the top part of the segment to the new segment
  for i in cutoff..<segment.len:
    top.values.add(segment.values[i])

  # resize the bottom part
  segment.values.setLen(cutoff)

  if top.min < sort:
    top.add(value, sort)
  else:
    segment.add(value, sort)

  top.next = segment.next
  top.prev = segment
  segment.next = top

  if top.next.isNil:
    list.tail = top
  else:
    top.next.prev = top

proc newNunroll*[S, V](sort: proc(v: V): S): List[S, V] =
  result = List[S, V](
    sort: sort
  )

proc add*[S, V](list: var List[S, V], value: V) =
  let sort = list.sort(value)
  let found = list.findSegment(sort)
  list.count += 1

  if found.rel == Relative.Self:
    if found.segment.len < DENSITY:
      found.segment.add(value, sort)
    else:
      list.split(found.segment, value, sort)
    return

  let segment = newSegment(value, sort)
  case found.rel:
    of Relative.Before:
      segment.next = found.segment
      segment.prev = found.segment.prev
      found.segment.prev = segment

      if segment.prev.isNil:
        list.head = segment
      else:
        segment.prev.next = segment

    of Relative.After:
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

proc len*[S, V](list: List[S, V]): int {.inline.} = list.count

iterator pairs*[S, V](list: List[S, V]): tuple[key: int, val: V] {.inline.} =
  var counter = 0
  for value in list.ranked:
    yield(counter, value.value)
    counter += 1

iterator items*[S, V](list: List[S, V]): V {.inline.} =
  for value in list.ranked: yield(value.value)

iterator ranked*[S, V](list: List[S, V]): Value[S, V] =
  var segment = list.head
  while not segment.isNil:
    for i in countup(0, <segment.len): yield segment.values[i]
    segment = segment.next

iterator rpairs*[S, V](list: List[S, V]): tuple[key: int, val: V] {.inline.} =
  var counter = 0
  for value in list.rranked:
    yield(counter, value.value)
    counter += 1

iterator ritems*[S, V](list: List[S, V]): V {.inline.} =
  for value in list.rranked: yield(value.value)

iterator rranked*[S, V](list: List[S, V]): Value[S, V] =
  var segment = list.tail
  while not segment.isNil:
    for i in countdown(<segment.len, 0): yield segment.values[i]
    segment = segment.prev
