include Alcotest_engine.Test

module Unix (M : Alcotest_engine.Monad.S) = struct
  module M = Alcotest_engine.Monad.Extend (M)
  module Fmt = Alcotest_engine.Private.Utils.Fmt

  module Unix = struct
    open Astring
    include Unix

    let mkdir_p path mode =
      let is_win_drive_letter x =
        String.length x = 2 && x.[1] = ':' && Char.Ascii.is_letter x.[0]
      in
      let sep = Filename.dir_sep in
      let rec mk parent = function
        | [] -> ()
        | name :: names ->
            let path = parent ^ sep ^ name in
            ( try Unix.mkdir path mode
              with Unix.Unix_error (Unix.EEXIST, _, _) ->
                if Sys.is_directory path then () (* the directory exists *)
                else Fmt.strf "mkdir: %s: is a file" path |> failwith );
            mk path names
      in
      match String.cuts ~empty:true ~sep path with
      | "" :: xs -> mk sep xs
      (* check for Windows drive letter *)
      | dl :: xs when is_win_drive_letter dl -> mk dl xs
      | xs -> mk "." xs
  end

  open M.Infix

  let time = Unix.time

  let getcwd = Sys.getcwd

  let prepare ~base ~dir ~name =
    if not (Sys.file_exists dir) then (
      Unix.mkdir_p dir 0o770;
      if Sys.unix || Sys.cygwin then (
        let this_exe = Filename.concat base name
        and latest = Filename.concat base "latest" in
        if Sys.file_exists this_exe then Sys.remove this_exe;
        if Sys.file_exists latest then Sys.remove latest;
        Unix.symlink ~to_dir:true dir this_exe;
        Unix.symlink ~to_dir:true dir latest ) )
    else if not (Sys.is_directory dir) then
      failwith (Fmt.strf "exists but is not a directory: %S" dir)

  let with_redirect file fn =
    M.return () >>= fun () ->
    Fmt.(flush stdout) ();
    Fmt.(flush stderr) ();
    let fd_stdout = Unix.descr_of_out_channel stdout in
    let fd_stderr = Unix.descr_of_out_channel stderr in
    let fd_old_stdout = Unix.dup fd_stdout in
    let fd_old_stderr = Unix.dup fd_stderr in
    let fd_file = Unix.(openfile file [ O_WRONLY; O_TRUNC; O_CREAT ] 0o660) in
    Unix.dup2 fd_file fd_stdout;
    Unix.dup2 fd_file fd_stderr;
    Unix.close fd_file;
    (try fn () >|= fun o -> `Ok o with e -> M.return @@ `Error e) >|= fun r ->
    Fmt.(flush stdout ());
    Fmt.(flush stderr ());
    Unix.dup2 fd_old_stdout fd_stdout;
    Unix.dup2 fd_old_stderr fd_stderr;
    Unix.close fd_old_stdout;
    Unix.close fd_old_stderr;
    match r with `Ok x -> x | `Error e -> raise e

  let setup_std_outputs = Fmt_tty.setup_std_outputs
end

module T = Alcotest_engine.Cli.Make (Unix) (Alcotest_engine.Monad.Identity)
include T

module Core = struct
  module Make = Alcotest_engine.Core.Make (Unix)
end

module Cli = struct
  module Make = Alcotest_engine.Cli.Make (Unix)
end