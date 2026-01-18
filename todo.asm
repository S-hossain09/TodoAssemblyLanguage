format ELF64 executable

include "linux.inc"

; Configuration constants
MAX_CONN equ 5                  ; Maximum pending connections in listen queue
REQUEST_CAP equ 128*1024        ; Maximum HTTP request size (128KB)
TODO_SIZE equ 256               ; Size of each todo item (1 byte length + 255 bytes content)
TODO_CAP equ 256                ; Maximum number of todos

segment readable executable

include "utils.inc"

entry main
main:
    ; Load existing todos from database file
    call load_todos

    funcall2 write_cstr, STDOUT, start

    ; Create TCP socket
    funcall2 write_cstr, STDOUT, socket_trace_msg
    socket AF_INET, SOCK_STREAM, 0
    cmp rax, 0
    jl .fatal_error
    mov qword [sockfd], rax

    ; Enable address reuse to avoid "Address already in use" errors
    setsockopt [sockfd], SOL_SOCKET, SO_REUSEADDR, enable, 4
    cmp rax, 0
    jl .fatal_error

    ; Enable port reuse for faster restart
    setsockopt [sockfd], SOL_SOCKET, SO_REUSEPORT, enable, 4
    cmp rax, 0
    jl .fatal_error

    ; Bind socket to port 14619 (0x391B in hex) on all interfaces
    funcall2 write_cstr, STDOUT, bind_trace_msg
    mov word [servaddr.sin_family], AF_INET
    mov word [servaddr.sin_port], 14619
    mov dword [servaddr.sin_addr], INADDR_ANY
    bind [sockfd], servaddr.sin_family, sizeof_servaddr
    cmp rax, 0
    jl .fatal_error

    ; Start listening for connections
    funcall2 write_cstr, STDOUT, listen_trace_msg
    listen [sockfd], MAX_CONN
    cmp rax, 0
    jl .fatal_error

.next_request:
    ; Accept incoming client connection
    funcall2 write_cstr, STDOUT, accept_trace_msg
    accept [sockfd], cliaddr.sin_family, cliaddr_len
    cmp rax, 0
    jl .fatal_error

    mov qword [connfd], rax

    ; Read HTTP request from client
    read [connfd], request, REQUEST_CAP
    cmp rax, 0
    jl .fatal_error
    mov [request_len], rax

    ; Initialize request cursor for parsing
    mov [request_cur], request

    ; Echo request to stdout for debugging
    write STDOUT, [request_cur], [request_len]

    ; Parse HTTP method - check for GET
    funcall4 starts_with, [request_cur], [request_len], get, get_len
    cmp rax, 0
    jg .handle_get_method

    ; Check for POST
    funcall4 starts_with, [request_cur], [request_len], post, post_len
    cmp rax, 0
    jg .handle_post_method

    ; Unknown method - return 405
    jmp .serve_error_405

.handle_get_method:
    ; Skip past "GET " in request
    add [request_cur], get_len
    sub [request_len], get_len

    ; Check if route is "/ " (index page)
    funcall4 starts_with, [request_cur], [request_len], index_route, index_route_len
    call starts_with
    cmp rax, 0
    jg .serve_index_page

    jmp .serve_error_404

.handle_post_method:
    ; Skip past "POST " in request
    add [request_cur], post_len
    sub [request_len], post_len

    ; Check for POST to index route (add/delete todo)
    funcall4 starts_with, [request_cur], [request_len], index_route, index_route_len
    cmp rax, 0
    jg .process_add_or_delete_todo_post

    ; Check for POST to shutdown route
    funcall4 starts_with, [request_cur], [request_len], shutdown_route, shutdown_route_len
    cmp rax, 0
    jg .process_shutdown

    jmp .serve_error_404

.process_shutdown:
    ; Send shutdown confirmation and exit
    funcall2 write_cstr, [connfd], shutdown_response
    jmp .shutdown

.process_add_or_delete_todo_post:
    ; Skip HTTP headers to get to POST body
    call drop_http_header
    cmp rax, 0
    je .serve_error_400

    ; Check if form data is for adding a todo
    funcall4 starts_with, [request_cur], [request_len], todo_form_data_prefix, todo_form_data_prefix_len
    cmp rax, 0
    jg .add_new_todo_and_serve_index_page

    ; Check if form data is for deleting a todo
    funcall4 starts_with, [request_cur], [request_len], delete_form_data_prefix, delete_form_data_prefix_len
    cmp rax, 0
    jg .delete_todo_and_serve_index_page

    jmp .serve_error_400

.serve_index_page:
    ; Send HTTP 200 response with HTML page
    funcall2 write_cstr, [connfd], index_page_response
    funcall2 write_cstr, [connfd], index_page_header
    call render_todos_as_html
    funcall2 write_cstr, [connfd], index_page_footer
    close [connfd]
    jmp .next_request

.serve_error_400:
    funcall2 write_cstr, [connfd], error_400
    close [connfd]
    jmp .next_request

.serve_error_404:
    funcall2 write_cstr, [connfd], error_404
    close [connfd]
    jmp .next_request

.serve_error_405:
    funcall2 write_cstr, [connfd], error_405
    close [connfd]
    jmp .next_request

.add_new_todo_and_serve_index_page:
    ; Skip "todo=" prefix to get actual todo text
    add [request_cur], todo_form_data_prefix_len
    sub [request_len], todo_form_data_prefix_len

    ; Add the new todo and persist to disk
    funcall2 add_todo, [request_cur], [request_len]
    call save_todos
    jmp .serve_index_page

.delete_todo_and_serve_index_page:
    ; Skip "delete=" prefix to get todo index
    add [request_cur], delete_form_data_prefix_len
    sub [request_len], delete_form_data_prefix_len

    ; Parse index as integer and delete the todo
    funcall2 parse_uint, [request_cur], [request_len]
    mov rdi, rax
    call delete_todo
    call save_todos
    jmp .serve_index_page

.shutdown:
    funcall2 write_cstr, STDOUT, ok_msg
    close [connfd]
    close [sockfd]
    exit 0

.fatal_error:
    funcall2 write_cstr, STDERR, error_msg
    close [connfd]
    close [sockfd]
    exit 1

; Skips HTTP headers to reach the POST body
; Returns 1 in rax if successful, 0 if invalid
drop_http_header:
.next_line:
    ; Check for CRLF CRLF (end of headers)
    funcall4 starts_with, [request_cur], [request_len], clrs, 2
    cmp rax, 0
    jg .reached_end

    ; Find next newline character
    funcall3 find_char, [request_cur], [request_len], 10
    cmp rax, 0
    je .invalid_header

    ; Move cursor past this line
    mov rsi, rax
    sub rsi, [request_cur]
    inc rsi
    add [request_cur], rsi
    sub [request_len], rsi

    jmp .next_line

.reached_end:
    ; Skip the final CRLF
    add [request_cur], 2
    sub [request_len], 2
    mov rax, 1
    ret

.invalid_header:
    xor rax, rax
    ret

; Deletes todo at index rdi by shifting remaining todos left
delete_todo:
   ; Calculate byte offset of todo to delete
   mov rax, TODO_SIZE
   mul rdi
   cmp rax, [todo_end_offset]
   jge .overflow

   ; Copy all todos after deleted one to fill the gap
   mov rdi, todo_begin
   add rdi, rax
   mov rsi, todo_begin
   add rsi, rax
   add rsi, TODO_SIZE
   mov rdx, todo_begin
   add rdx, [todo_end_offset]
   sub rdx, rsi
   call memcpy

   ; Decrease total size
   sub [todo_end_offset], TODO_SIZE
.overflow:
   ret

; Loads todos from database file into memory
load_todos:
   sub rsp, 16
   mov qword [rsp+8], -1     ; File descriptor
   mov qword [rsp], 0        ; File size

   ; Open database file for reading
   open todo_db_file_path, O_RDONLY, 0
   cmp rax, 0
   jl .error
   mov [rsp+8], rax

   ; Get file size using fstat
   fstat64 [rsp+8], statbuf
   cmp rax, 0
   jl .error

   mov rax, statbuf
   add rax, stat64.st_size
   mov rax, [rax]
   mov [rsp], rax

   ; Verify file size is multiple of TODO_SIZE
   mov rcx, TODO_SIZE
   div rcx
   cmp rdx, 0
   jne .error

   ; Limit read size to maximum capacity
   mov rcx, TODO_CAP*TODO_SIZE
   mov rax, [rsp]
   cmp rax, rcx
   cmovg rax, rcx
   mov [rsp], rax

   ; Read todos into memory
   read [rsp+8], todo_begin, [rsp]
   mov rax, [rsp]
   mov [todo_end_offset], rax

.error:
   close [rsp+8]
   add rsp, 16
   ret

; Writes all todos from memory to database file
save_todos:
   ; Create/truncate file with read/write permissions (0644)
   open todo_db_file_path, O_CREAT or O_WRONLY or O_TRUNC, 420
   cmp rax, 0
   jl .fail
   push rax
   write qword [rsp], todo_begin, [todo_end_offset]
   close qword [rsp]
   pop rax
.fail:
   ret

; Adds a new todo item
; rdi = pointer to todo text, rsi = length of text
add_todo:
   ; Check if we've reached maximum capacity
   cmp qword [todo_end_offset], TODO_SIZE*TODO_CAP
   jge .capacity_overflow

   ; Truncate text longer than 255 bytes
   mov rax, 0xFF
   cmp rsi, rax
   cmovg rsi, rax

   push rdi 
   push rsi 

   ; Write length byte followed by todo text
   mov rdi, todo_begin
   add rdi, [todo_end_offset]
   mov rdx, [rsp]
   mov byte [rdi], dl        ; Store length as first byte
   inc rdi
   mov rsi, [rsp+8]
   call memcpy

   ; Update end offset
   add [todo_end_offset], TODO_SIZE

   pop rsi
   pop rdi
   mov rax, 0
   ret
.capacity_overflow:
   mov rax, 1
   ret

; Renders all todos as HTML list items
render_todos_as_html:
    push 0                    ; Todo index counter
    push todo_begin           ; Current todo pointer
.next_todo:
    ; Check if we've processed all todos
    mov rax, [rsp]
    mov rbx, todo_begin
    add rbx, [todo_end_offset]
    cmp rax, rbx
    jge .done

    ; Write HTML for this todo (delete button + text)
    funcall2 write_cstr, [connfd], todo_header
    funcall2 write_cstr, [connfd], delete_button_prefix
    funcall2 write_uint, [connfd], [rsp+8]
    funcall2 write_cstr, [connfd], delete_button_suffix

    ; Write todo text (length is in first byte)
    mov rax, SYS_write
    mov rdi, [connfd]
    mov rsi, [rsp]
    xor rdx, rdx
    mov dl, byte [rsi]        ; Get length from first byte
    inc rsi                   ; Skip to actual text
    syscall

    funcall2 write_cstr, [connfd], todo_footer
    
    ; Move to next todo
    mov rax, [rsp]
    add rax, TODO_SIZE
    mov [rsp], rax
    inc qword [rsp+8]
    jmp .next_todo
.done:
    pop rax
    pop rax
    ret

segment readable writeable

; Socket and server data structures
enable dd 1
sockfd dq -1
connfd dq -1
servaddr servaddr_in
sizeof_servaddr = $ - servaddr.sin_family
cliaddr servaddr_in
cliaddr_len dd sizeof_servaddr

; HTTP parsing helpers
clrs db 13, 10                ; CRLF sequence

; HTTP error responses
error_400            db "HTTP/1.1 400 Bad Request", CARRIAGE_RETURN, NEW_LINE
                     db "Content-Type: text/html; charset=utf-8", CARRIAGE_RETURN, NEW_LINE
                     db "Connection: close", CARRIAGE_RETURN, NEW_LINE
                     db CARRIAGE_RETURN, NEW_LINE
                     db "<h1>Bad Request</h1>", NEW_LINE
                     db "<a href='/'>Back to Home</a>", NEW_LINE
                     db END_OF_STRING

                     
error_404            db "HTTP/1.1 404 Not found", CARRIAGE_RETURN, NEW_LINE
                     db "Content-Type: text/html; charset=utf-8", CARRIAGE_RETURN, NEW_LINE
                     db "Connection: close", CARRIAGE_RETURN, NEW_LINE
                     db CARRIAGE_RETURN, NEW_LINE
                     db "<h1>Page not found</h1>", NEW_LINE
                     db "<a href='/'>Back to Home</a>", NEW_LINE
                     db END_OF_STRING

                     
error_405            db "HTTP/1.1 405 Method Not Allowed", CARRIAGE_RETURN, NEW_LINE
                     db "Content-Type: text/html; charset=utf-8", CARRIAGE_RETURN, NEW_LINE
                     db "Connection: close", CARRIAGE_RETURN, NEW_LINE
                     db CARRIAGE_RETURN, NEW_LINE
                     db "<h1>Method not Allowed</h1>", NEW_LINE
                     db "<a href='/'>Back to Home</a>", NEW_LINE
                     db END_OF_STRING

                     
index_page_response  db "HTTP/1.1 200 OK", CARRIAGE_RETURN, NEW_LINE
                     db "Content-Type: text/html; charset=utf-8", CARRIAGE_RETURN, NEW_LINE
                     db "Connection: close", CARRIAGE_RETURN, NEW_LINE
                     db CARRIAGE_RETURN, NEW_LINE
                     db END_OF_STRING

                     
index_page_header    db "<h1>To-Do</h1>", NEW_LINE
                     db "<ul>", NEW_LINE
                     db END_OF_STRING

                     
index_page_footer    db "  <li>", NEW_LINE
                     db "    <form style='display: inline' method='post' action='/' enctype='text/plain'>", NEW_LINE
                     db "        <input style='width: 25px' type='submit' value='+'>", NEW_LINE
                     db "        <input type='text' name='todo' autofocus>", NEW_LINE
                     db "    </form>", NEW_LINE
                     db "  </li>", NEW_LINE
                     db "</ul>", NEW_LINE
                     db "<form method='post' action='/shutdown'>", NEW_LINE
                     db "    <input type='submit' value='shutdown'>", NEW_LINE
                     db "</form>", NEW_LINE
                     db END_OF_STRING

                     
todo_header          db "  <li>"
                     db END_OF_STRING

                     
todo_footer          db "</li>", NEW_LINE
                     db END_OF_STRING

                     
delete_button_prefix db "<form style='display: inline' method='post' action='/'>"
                     db "<button style='width: 25px' type='submit' name='delete' value='"
                     db END_OF_STRING

                     
delete_button_suffix db "'>x</button></form> "
                     db END_OF_STRING

                     
shutdown_response    db "HTTP/1.1 200 OK", CARRIAGE_RETURN, NEW_LINE
                     db "Content-Type: text/html; charset=utf-8", CARRIAGE_RETURN, NEW_LINE
                     db "Connection: close", CARRIAGE_RETURN, NEW_LINE
                     db CARRIAGE_RETURN, NEW_LINE
                     db "<h1>Shutting down the server...</h1>", NEW_LINE
                     db "Please close this tab"
                     db END_OF_STRING

                     

; Form data prefixes for parsing POST requests
todo_form_data_prefix db "todo="
todo_form_data_prefix_len = $ - todo_form_data_prefix
delete_form_data_prefix db "delete="
delete_form_data_prefix_len = $ - delete_form_data_prefix

; HTTP method strings
get db "GET "
get_len = $ - get
post db "POST "
post_len = $ - post

; Route strings
index_route db "/ "
index_route_len = $ - index_route

shutdown_route db "/shutdown "
shutdown_route_len = $ - shutdown_route

; END_OF_STRING

; Logging messages
start            db "INFO: Starting Web Server!", NEW_LINE, END_OF_STRING
ok_msg           db "INFO: OK!", NEW_LINE, END_OF_STRING
socket_trace_msg db "INFO: Creating a socket...", NEW_LINE, END_OF_STRING
bind_trace_msg   db "INFO: Binding the socket...", NEW_LINE, END_OF_STRING
listen_trace_msg db "INFO: Listening to the socket...", NEW_LINE, END_OF_STRING
accept_trace_msg db "INFO: Waiting for client connections...", NEW_LINE, END_OF_STRING
error_msg        db "FATAL ERROR!", NEW_LINE, END_OF_STRING

todo_db_file_path db "todo.db", END_OF_STRING

; Request buffer and parsing state
request_len rq 1
request_cur rq 1
request     rb REQUEST_CAP

; Todo storage (array of 256-byte items: 1 byte length + 255 bytes data)
todo_begin rb TODO_SIZE*TODO_CAP
todo_end_offset rq 1

; File stat buffer for fstat64 syscall
statbuf rb sizeof_stat64