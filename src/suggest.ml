(* "Did you mean": the closest known name to an unknown one. *)

(* The number of single-character insertions, deletions, changes, and swaps
   of two neighbouring characters that turn [a] into [b]. Counting a swap as
   one edit catches typos like 'i23' for 'i32'. *)
let distance a b =
  let n = String.length a in
  let m = String.length b in
  let d = Array.make_matrix (n + 1) (m + 1) 0 in
  for i = 0 to n do
    d.(i).(0) <- i
  done;
  for j = 0 to m do
    d.(0).(j) <- j
  done;
  for i = 1 to n do
    for j = 1 to m do
      let cost = if a.[i - 1] = b.[j - 1] then 0 else 1 in
      let best =
        min
          (min (d.(i - 1).(j) + 1) (d.(i).(j - 1) + 1))
          (d.(i - 1).(j - 1) + cost)
      in
      let best =
        if i > 1 && j > 1 && a.[i - 1] = b.[j - 2] && a.[i - 2] = b.[j - 1] then
          min best (d.(i - 2).(j - 2) + 1)
        else best
      in
      d.(i).(j) <- best
    done
  done;
  d.(n).(m)

(* The best candidate so far: its name, distance, and order (lower means
   declared earlier, which wins a tie). *)
type best = { name : string; dist : int; order : int }

let consider target limit (best : best option) (candidate, order) =
  let dist = distance target candidate in
  if dist = 0 || dist > limit then best
  else
    match best with
    | Some b when b.dist < dist || (b.dist = dist && b.order <= order) -> best
    | _ -> Some { name = candidate; dist; order }

(* The closest of [candidates], each a name with its order, if it is within
   one edit per three characters of [target] (and at least one). *)
let closest target (candidates : (string * int) list) =
  let limit = max 1 (String.length target / 3) in
  match List.fold_left (consider target limit) None candidates with
  | Some b -> Some b.name
  | None -> None
