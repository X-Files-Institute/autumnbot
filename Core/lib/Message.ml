(** The MIT License (MIT)
 ** 
 ** Copyright (c) 2022 Muqiu Han
 ** 
 ** Permission is hereby granted, free of charge, to any person obtaining a copy
 ** of this software and associated documentation files (the "Software"), to deal
 ** in the Software without restriction, including without limitation the rights
 ** to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 ** copies of the Software, and to permit persons to whom the Software is
 ** furnished to do so, subject to the following conditions:
 ** 
 ** The above copyright notice and this permission notice shall be included in all
 ** copies or substantial portions of the Software.
 ** 
 ** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 ** IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 ** FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 ** AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 ** LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 ** OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 ** SOFTWARE. *)

open Domain.Message

let log_location : string = "Message"

let parse_body : Yojson.Basic.t -> string =
 fun json ->
  let open Yojson.Basic.Util in
  match json |> member "body" with
  | `Null -> raise (Yojson.Json_error "The body field is not included in the message!")
  | `String body -> body
  | _ -> raise (Yojson.Json_error "body format is invalid!")
;;

let parse_header : Yojson.Basic.t -> message_header =
 fun json ->
  let open Yojson.Basic.Util in
  match json |> member "header" with
  | `Null -> raise (Yojson.Json_error "The header field is not included in the message!")
  | `Assoc [ ("self", `String self); ("target", `String target) ] -> { self; target }
  | _ -> raise (Yojson.Json_error "header format is invalid!")
;;

let parse : string -> (message, string) result =
 fun raw_message ->
  try
    let json : Yojson.Basic.t = Yojson.Basic.from_string raw_message in
    let header = parse_header json
    and body = parse_body json in
    if String.starts_with ~prefix:"AutumnBot.Client" header.self
    then Ok (Client_Message { header; body })
    else if String.starts_with ~prefix:"AutumnBot.Service" header.self
    then Ok (Service_Message { header; body })
    else
      raise (Yojson.Json_error (Format.sprintf "Unknown message source: %s" header.self))
  with
  | Yojson.Json_error error_msg ->
    Log.error log_location error_msg;
    Error error_msg
;;

let build_error_message : string -> string =
 fun err_msg ->
  Format.sprintf
    {|
      { "header": {
          "self": "core",
          "target" : ""
        },
        "body" : "%s" }
    |}
    err_msg
;;

module Pool = struct
  type pool =
    { queue : t Queue.t
    ; mutex : Mutex.t
    ; nonempty : Condition.t
    }

  let create () =
    { queue = Queue.create (); mutex = Mutex.create (); nonempty = Condition.create () }
  ;;

  let add : t -> pool -> unit Lwt.t =
   fun v q ->
    Mutex.lock q.mutex;
    let was_empty = Queue.is_empty q.queue in
    Log.info log_location "add";
    Queue.add v q.queue;
    if was_empty then Condition.broadcast q.nonempty;
    Mutex.unlock q.mutex |> Lwt.return
 ;;

  let take : pool -> t Lwt.t =
   fun q ->
    Mutex.lock q.mutex;
    while Queue.is_empty q.queue do
      Condition.wait q.nonempty q.mutex
    done;
    let v = Queue.take q.queue in
    Mutex.unlock q.mutex;
    Log.info log_location "take";
    Lwt.return v
 ;;

  type t = pool
end

let message_pool : Pool.t = Pool.create ()

let push : Dream.websocket -> string -> (unit, string) result Lwt.t =
 fun connection raw_message ->
  match parse raw_message with
  | Ok message -> Lwt.(Pool.add (connection, message) message_pool >>= Lwt.return_ok)
  | Error msg -> Error msg |> Lwt.return
;;

let pop : unit -> (Domain.Dispatcher.instruction * Dream.websocket) Lwt.t =
 fun () ->
  Lwt.(
    Pool.take message_pool
    >>= fun (connection, msg) ->
    let instruction =
      match msg with
      | Client_Message msg ->
        Domain.Dispatcher.Request
          { request_self = msg.header.self
          ; request_service = msg.header.target
          ; request_body = msg.body
          }
      | Service_Message msg ->
        Domain.Dispatcher.Reply
          { reply_self = msg.header.self
          ; reply_client = msg.header.target
          ; reply_body = msg.body
          }
    in
    Lwt.return (instruction, connection))
;;