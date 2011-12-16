/*
    Copyright © 2011 MLstate

    This file is part of OPA.

    OPA is free software: you can redistribute it and/or modify it under the
    terms of the GNU Affero General Public License, version 3, as published by
    the Free Software Foundation.

    OPA is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
    FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public License for
    more details.

    You should have received a copy of the GNU Affero General Public License
    along with OPA.  If not, see <http://www.gnu.org/licenses/>.
*/

/**
 * @author Adam Koprowski, Hugo Heuzard 2011
 *
 * @destination public
 */

import stdlib.crypto

/**
 * {1 Types}
 */

type Email.address = {local: string ; domain: string}

/**
 * This type represents an email address, it contains two fields [name] and [address],
 * where [name] is a optional user-friendly name (string) and [address] is an email address.
 * For instance
 * "John Smith" <john.smith@some.server.com>
 * will give the following data instance:
 * [{ name = some("John Smith"); address = john.smith@some.server.com }].
 */
type Email.email = { name : option(string) ; address : Email.address }

/**
 * Type of a file attachment
 */
type Email.file =
  {filename : string content: string mime_type: string}
/ {filename : string content: string mime_type: string encoding:string}
/ {filename : string resource: resource}

/**
 * A list of file attachments
 */
type Email.attachments = list(Email.file)

/**
 * Type of an email content
 * if you give {~html} then a text will be computed out of the xhtml,
 * to be non html part to your email
 */
type Email.content =
  {text:string}
/ {html:xhtml}
/ {text:string html:xhtml}

type Email.send_status =
   { bad_sender }
 / { bad_recipient }
 / { sending }
 / { ok }
 / { error : string }

type Email.options = {
  custom_headers : list((string, string))
}

type caml_tuple_2('a,'b) = external
type caml_tuple_4('a,'b,'c,'d) = external

/**
 * This module is meant to deal with email address and email sending
 */
Email = {{

  default_options = {
    custom_headers = []
  } : Email.options

  @private
  send_mail = %% BslMail.Mailserve.mail_send_fun %% : string , string , string , string, string, caml_list(caml_tuple_4(string,string,string,string)), caml_list(caml_tuple_2(string, string)), (Email.send_status -> void) -> void

  /**
   * {1 Parsing email addresses}
   */

  /**
   * A parser for an email address giving a value of type {!Email.email}.
   * An email address should be of the form:
   *  John Smith <john.smith@some.server.com>
   * or
   *  john.smith@some.server.com
   *
   * For a more detailed description of the accepted format of emails see:
   * {{:http://en.wikipedia.org/wiki/E-mail_address#RFC_specification}E-mail address: RFC specification (Wikipedia)}
   */
  @private
  dblquote = parser [\"];

  email_parser : Parser.general_parser(Email.email) =
    email_name =
      parser
        // we either have a name in double quotes (needs to be followed by "<" for the address), "..." <...>
      | dblquote name=(!dblquote .)* dblquote Rule.ws &[<] -> Text.ltconcat(name) |> Text.to_string |> some
        // or a name without double quotes (again needs to be followed by "<"), ... <...>
      | name=(![<] .)* &[<] -> Text.ltconcat(name) |> Text.to_string |> String.trim |> some
        // otherwise there's no name component
      | {Rule.succeed} -> none
    email_address =
      parser
        // email address can be in between angle brackets <...>
      | [<] Rule.ws email=address_parser Rule.ws [>] -> email
        // ... or without them
      | email=address_parser -> email
    parser Rule.ws name=email_name Rule.ws address=email_address Rule.ws -> ~{name address}

  email_simple_parser : Parser.general_parser(Email.email) = parser Rule.ws email=address_parser Rule.ws -> {name=none ; address=email}

  /**
   * A parser accepting characters allowed as parts of an email
   * address, that is:
   *  - small and capital letters,
   *  - digits,
   *  - characters: underscore (_), hyphen (-)
   * Here we are more restrictive than the RFC specification, but
   * are in accordance with common practice (for instance HotMail's
   * requirements on email addresses).
   */
  @private
  char = parser [A-Za-z0-9_\-];

  @private
  word = parser w=char+ -> Text.to_string(Text.ltconcat(w))

  /**
   * A parser for a local part of the email address, i.e.
   * a series of email allowed {!char}s, separated by dots.
   */
  @private
  local = Rule.parse_list_sep_min_length(1, false, word, parser "." -> void)
   // full RFC compilant list of special characters: ! # $ % & ' * + - / = ? ^ _ ` { | }

  /**
   * A parser for an email address, i.e. a local part of the
   * address ({!id}), followed by the 'at' character (@),
   * followed by the {!domain} address.
   */
  address_parser : Parser.general_parser(Email.address) = parser local=local [@] domain=UriParser.domain -> {local=String.concat(".",local) ~domain};

  /**
   * Convertion from a string to email.
   *
   * @param s string for conversion.
   * @return optional email represented by the given string.
   */
  of_string_opt(s:string) = Parser.try_parse(Email.email_parser, s)

  /**
   * Convertion from a string to email.
   *
   * @param s string for conversion.
   * @return email represented by the given string or error
   *         if [s] did not represesent a valid email address.
   */
  of_string(s:string) =
    of_string_opt(s) ? error("Wrong email: {s}")

  @stringifier(Email.email) to_string(email) =
    match email.name with
      | {~some} -> "\"{some}\" <{email.address.local}@{email.address.domain}>"
      | {none} -> "{email.address.local}@{email.address.domain}"

  @xmlizer(Email.email) to_xml(email) =
    <>{"{email}"}</>

  to_string_only_address(email) =
    "{email.address.local}@{email.address.domain}"

  is_valid_string(s : string) = Option.is_some(of_string_opt(s))

  /**
   * {1} Sending Email.
   */

  string_of_send_status(s : Email.send_status) =
    match s with
    | { bad_sender } -> "bad sender"
    | { bad_recipient } -> "bad recipient"
    | { sending } -> "sending"
    | { ok } -> "ok"
    | { error=e } -> "error : {e}"

  @private
  private_send_async(
    from : Email.email,
    to : Email.email,
    subject : string,
    mail_content : Email.content,
    files : option(Email.attachments),
    options : Email.options,
    k : (Email.send_status -> void)) : void =
    caml_list2(l) =
      rec aux(l,acc) =
        match l with
          | [] -> acc
          | [hd|tl] -> aux(tl, %%BslNativeLib.cons%%(%%BslNativeLib.ocaml_tuple_2%%(hd),acc))
      aux(List.rev(l),%%BslNativeLib.empty_list%%)
    caml_list4(l) =
      rec aux(l,acc) =
        match l with
          | [] -> acc
          | [hd|tl] -> aux(tl, %%BslNativeLib.cons%%(%%BslNativeLib.ocaml_tuple_4%%(hd),acc))
      aux(List.rev(l),%%BslNativeLib.empty_list%%)
    (text,html) = match mail_content with
      | {~text} -> (text,"")
      | {~text ~html} -> (text,Xhtml.serialize_as_standalone_html(html))
      | {~html} -> (Xhtml.to_readable_string(html),Xhtml.serialize_as_standalone_html(html))
    end
    files = match files with
      | {none} -> caml_list4([])
      | {some=list_files} ->
        files = List.filter_map((x -> match x with
          | ~{filename content mime_type} ->
             if String.check_substring(mime_type,0,"text/")
             then some((filename,mime_type,"8bit",content))
             else some((filename,mime_type,"base64",Crypto.Base64.encode(content)))
          | ~{filename content mime_type encoding} -> some((filename,mime_type,encoding,content))
          | ~{filename resource} ->
             (match Resource.export_data(resource) with
               | {some=~{data mimetype}} ->
                 if String.check_substring(mimetype,0,"text/")
                 then some((filename,mimetype,"8bit",data))
                 else some((filename,mimetype,"base64",Crypto.Base64.encode(data)))
               | {none} -> {none}
             end))
          ,list_files)
        caml_list4(files)
        end
    custom_headers = caml_list2(options.custom_headers)
    send_mail(to_string_only_address(from), to_string_only_address(to), subject, text, html, files, custom_headers, k)

  /** Try to send a mail synchronously */
  try_send(from : Email.email, to : Email.email, subject : string, content : Email.content, options : Email.options) : Email.send_status =
    k(cont) =
      f(r) = Continuation.return(cont, r)
      private_send_async(from, to, subject, content, none, options, f)
    @callcc(k)

  /** Try to send a mail asynchronously */
  try_send_async(from : Email.email, to : Email.email, subject : string, content : Email.content, options : Email.options, continuation : (Email.send_status -> void)) : void =
    private_send_async(from, to, subject, content, none, options, continuation)

  /** Try to send a mail containing files synchronously */
  try_send_with_files(from : Email.email, to : Email.email, subject : string, content : Email.content, files : Email.attachments, options : Email.options) : Email.send_status =
    k(cont) =
      f(r) = Continuation.return(cont, r)
      private_send_async(from, to, subject, content, some(files), options, f)
    @callcc(k)

  /** Try to send a mail containing files asynchronously */
  try_send_with_files_async(from : Email.email, to : Email.email, subject : string, content : Email.content, files : Email.attachments, options : Email.options, continuation : (Email.send_status -> void)) : void =
    private_send_async(from, to, subject, content, some(files), options, continuation)

}}
