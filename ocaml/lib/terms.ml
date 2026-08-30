(* Terms — the bounded contract a gig runs under.
 *
 * One value carrying grants AND budget AND expiry, checked per action. That
 * coupling is the point: budget exhaustion and ungranted action are the same
 * mechanism, so an approved gig cannot burn unbounded actions inside itself.
 *
 * A budget number sitting in a table that nothing reads is not a budget. This
 * has to be threaded through every action to mean anything.
 *
 * Terms are an ACL: the actor asks, the terms answer. That is deliberately NOT
 * what Caps is. A capability dirfd cannot express "twenty reads then stop";
 * Terms cannot stop a path escape. Spatial bounds come from the kernel via
 * Caps, quantitative bounds come from here, and both are threaded together. *)

type breach =
  | Expired of { at : int64; now : int64 }
  | Exhausted of { budget : int }
  | Not_granted of Grants.action

let breach_to_string = function
  | Expired { at; now } ->
      Printf.sprintf "terms expired at %Ld, now %Ld" at now
  | Exhausted { budget } ->
      Printf.sprintf "budget of %d actions exhausted" budget
  | Not_granted a ->
      Printf.sprintf "action %s not granted" (Grants.action_to_string a)

type t = {
  id         : string;
  grants     : Grants.t;
  budget     : int;
  consumed   : int;
  expires_at : int64;
}

let issue ~id ~grants ~budget ~expires_at =
  { id; grants; budget; consumed = 0; expires_at }

let consume t = { t with consumed = t.consumed + 1 }

(* Is this contract still alive, independent of any action?
 *
 * Split out from `check` because the booker has to ask exactly this and has no
 * action to name yet -- it is deciding whether to issue a gig at all. Forcing
 * it to invent an action to interrogate the terms would have made the answer
 * depend on which action it picked, which is not a property of the terms.
 *
 * Order matters: expiry first, because a lapsed contract should not report a
 * budget figure as though it were still live. *)
let live t ~now =
  if Int64.compare now t.expires_at >= 0 then
    Error (Expired { at = t.expires_at; now })
  else if t.consumed >= t.budget then
    Error (Exhausted { budget = t.budget })
  else Ok ()

let check t ~now ~action =
  match live t ~now with
  | Error e -> Error e
  | Ok () ->
      if not (Grants.allows t.grants action) then Error (Not_granted action)
      else Ok ()

(* Debit one unit with no action named. The booker spends this per GIG, in the
 * parent, before the fork -- see booking.ml. Deliberately NOT expressible as
 * `spend ~action:Spawn`: a kit with no grants at all (echo) would then be
 * unbookable, and the thing being counted here is the booking, not a step. *)
let tick t ~now =
  match live t ~now with
  | Error e -> Error e
  | Ok () -> Ok { t with consumed = t.consumed + 1 }

(* Check and spend in one step, so a caller cannot check then act twice. *)
let spend t ~now ~action =
  match check t ~now ~action with
  | Ok () -> Ok (consume t)
  | Error e -> Error e

let remaining t = max 0 (t.budget - t.consumed)
let grants t = t.grants
let id t = t.id
let expires_at t = t.expires_at
let consumed t = t.consumed
let budget t = t.budget
