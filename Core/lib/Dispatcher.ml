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

open Domain.Dispatcher

let log_location : string = "Dispatcher"

let handle : instruction -> unit Lwt.t = function
  | Reply { reply_self; reply_client; reply_body } ->
    Lwt.(
      Instance.get reply_client
      >>= fun client ->
      (match client with
       | Some client ->
         Dream.send
           client
           (Format.sprintf
              {|{ "header" : { "service": "%s" }, body : "%s" } |}
              reply_self
              reply_body)
       | None -> Lwt.return_unit))
  | Request { request_self; request_service; request_body } ->
    Lwt.(
      Instance.get request_service
      >>= fun service ->
      (match service with
       | Some service ->
         Dream.send
           service
           (Format.sprintf
              {| { "header" : { "client": "%s }, body : "%s" } |}
              request_self
              request_body)
       | None -> Lwt.return_unit))
;;

let dispatch : unit -> unit =
 fun _ ->
  Log.info log_location "start";
  let rec loop _ =
    Lwt.(Message.pop () >>= fun instruction -> handle instruction |> loop)
  in
  loop Lwt.return_unit |> ignore
;;
