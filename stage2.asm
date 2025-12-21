org 0x8000

section .text
start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    
    call init_fs
    
    mov ax, 0x0003
    int 0x10
    
main_loop:
    call print_prompt
    call read_command
    call process_command
    call print_newline
    jmp main_loop

print_prompt:
    mov si, prompt_str
    call print_string
    mov si, current_dir
    call print_string
    mov si, prompt_end
    call print_string
    ret

print_string:
    push ax
    push bx
    mov ah, 0x0E
    mov bh, 0
.loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .loop
.done:
    pop bx
    pop ax
    ret

print_newline:
    push ax
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
    pop ax
    ret

read_command:
    mov di, cmd_buffer
    xor cx, cx
.read_loop:
    mov ah, 0x00
    int 0x16
    
    cmp al, 0x0D
    je .done
    
    cmp al, 0x08
    je .backspace
    
    cmp al, 0x20
    jb .read_loop
    
    cmp cx, 127
    jae .read_loop
    
    stosb
    inc cx
    
    mov ah, 0x0E
    int 0x10
    jmp .read_loop
    
.backspace:
    cmp cx, 0
    je .read_loop
    
    dec di
    dec cx
    
    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .read_loop
    
.done:
    xor al, al
    stosb
    ret

process_command:
    mov si, cmd_buffer
    lodsb
    cmp al, 0
    je .empty
    
    mov si, cmd_buffer
    
    mov di, cmd_help
    call compare_cmd
    cmp ax, 1
    je .cmd_help
    
    mov di, cmd_clear
    call compare_cmd
    cmp ax, 1
    je .cmd_clear
    
    mov di, cmd_echo
    call compare_cmd
    cmp ax, 1
    je .cmd_echo
    
    mov di, cmd_bae
    call compare_cmd
    cmp ax, 1
    je .cmd_bae
    
    mov di, cmd_mkdir
    call compare_cmd
    cmp ax, 1
    je .cmd_mkdir
    
    mov di, cmd_cd
    call compare_cmd
    cmp ax, 1
    je .cmd_cd
    
    mov di, cmd_rp
    call compare_cmd
    cmp ax, 1
    je .cmd_rp
    
    mov di, cmd_ls
    call compare_cmd
    cmp ax, 1
    je .cmd_ls
    
    mov di, cmd_show
    call compare_cmd
    cmp ax, 1
    je .cmd_show
    
    mov di, cmd_reboot
    call compare_cmd
    cmp ax, 1
    je .cmd_reboot
    
    mov di, cmd_rm
    call compare_cmd
    cmp ax, 1
    je .cmd_rm
    
    call print_newline
    mov si, msg_unknown
    call print_string
    jmp .empty
    
.cmd_help:
    call print_newline
    mov si, msg_help
    call print_string
    jmp .empty
    
.cmd_clear:
    mov ax, 0x0003
    int 0x10
    jmp .empty
    
.cmd_echo:
    call print_newline
    mov si, cmd_buffer
    add si, 5
    call print_string
    jmp .empty
    
.cmd_bae:
    call handle_bae
    jmp .empty
    
.cmd_mkdir:
    call handle_mkdir
    jmp .empty
    
.cmd_cd:
    call handle_cd
    jmp .empty
    
.cmd_rp:
    call handle_rp
    jmp .empty
    
.cmd_ls:
    call handle_ls
    jmp .empty
    
.cmd_show:
    call handle_show
    jmp .empty
    
.cmd_reboot:
    call print_newline
    mov si, msg_reboot
    call print_string
    call print_newline
    db 0xEA
    dw 0x0000
    dw 0xFFFF
    
.cmd_rm:
    call handle_rm
    jmp .empty
    
.empty:
    ret

compare_cmd:
    push si
    push di
.loop:
    lodsb
    mov bl, al
    mov al, [di]
    inc di
    
    cmp bl, ' '
    je .check_end
    
    cmp bl, 'A'
    jb .no_lower1
    cmp bl, 'Z'
    ja .no_lower1
    add bl, 32
.no_lower1:
    
    cmp al, 'A'
    jb .no_lower2
    cmp al, 'Z'
    ja .no_lower2
    add al, 32
.no_lower2:
    
    cmp bl, al
    jne .not_equal
    
    cmp bl, 0
    je .equal
    jmp .loop
    
.check_end:
    cmp byte [di-1], 0
    je .equal
    jmp .not_equal
    
.equal:
    pop di
    pop si
    mov ax, 1
    ret
    
.not_equal:
    pop di
    pop si
    mov ax, 0
    ret

init_fs:
    mov di, fs_storage
    mov cx, 10240
    xor al, al
    rep stosb
    
    mov byte [current_dir], '/'
    mov byte [current_dir+1], 0
    ret

; Função auxiliar: compara path do arquivo/pasta com current_dir
is_in_current_dir:
    push si
    push di
    push cx
    
    ; di aponta para o registro (byte de tipo)
    ; O path está em di+33 (depois do nome de 32 bytes)
    lea si, [di+33]
    mov di, current_dir
    
.compare_loop:
    lodsb           ; carrega byte do path armazenado
    mov bl, [di]    ; carrega byte do current_dir
    inc di
    
    cmp al, bl
    jne .not_match
    
    cmp al, 0
    je .match
    jmp .compare_loop
    
.not_match:
    pop cx
    pop di
    pop si
    mov ax, 0
    ret
    
.match:
    pop cx
    pop di
    pop si
    mov ax, 1
    ret

handle_bae:
    call print_newline
    
    mov si, cmd_buffer
    add si, 4
    
.skip_space:
    lodsb
    cmp al, ' '
    je .skip_space
    dec si
    
    lodsb
    cmp al, 0
    je .no_name
    dec si
    
    mov di, temp_filename
    mov cx, 32
.copy_name:
    lodsb
    cmp al, 0
    je .name_done
    cmp al, ' '
    je .name_done
    stosb
    loop .copy_name
.name_done:
    xor al, al
    stosb
    
    call editor_loop
    call save_file
    ret
    
.no_name:
    mov si, msg_no_name
    call print_string
    ret

editor_loop:
    call print_newline
    mov si, msg_editor_help
    call print_string
    call print_newline
    call print_newline
    
    mov di, editor_buffer
    xor cx, cx
    
.edit_loop:
    mov ah, 0x00
    int 0x16
    
    cmp al, 19
    je .save
    
    cmp al, 3
    je .exit
    
    cmp al, 0x0D
    je .newline
    
    cmp al, 0x08
    je .backspace
    
    cmp al, 0x20
    jb .edit_loop
    
    cmp cx, 2047
    jae .edit_loop
    
    stosb
    inc cx
    
    mov ah, 0x0E
    int 0x10
    jmp .edit_loop
    
.newline:
    cmp cx, 2047
    jae .edit_loop
    
    mov al, 0x0D
    stosb
    inc cx
    mov al, 0x0A
    stosb
    inc cx
    
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
    jmp .edit_loop
    
.backspace:
    cmp cx, 0
    je .edit_loop
    
    dec di
    dec cx
    
    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .edit_loop
    
.save:
    mov word [editor_size], cx
    call print_newline
    mov si, msg_saved
    call print_string
    ret
    
.exit:
    mov word [editor_size], 0
    call print_newline
    ret

save_file:
    cmp word [editor_size], 0
    je .no_save
    
    mov di, fs_storage
    mov cx, 20
.find_slot:
    cmp byte [di], 0
    je .found_slot
    add di, 547
    loop .find_slot
    
    mov si, msg_fs_full
    call print_string
    ret
    
.found_slot:
    mov byte [di], 1
    inc di
    
    mov si, temp_filename
    mov cx, 32
    rep movsb
    
    ; Salvar o path completo (current_dir)
    mov si, current_dir
    mov cx, 32
    rep movsb
    
    mov ax, [editor_size]
    stosw
    
    mov si, editor_buffer
    mov cx, [editor_size]
    rep movsb
    
.no_save:
    ret

handle_mkdir:
    call print_newline
    
    mov si, cmd_buffer
    add si, 6
    
.skip_space:
    lodsb
    cmp al, ' '
    je .skip_space
    dec si
    
    lodsb
    cmp al, 0
    je .no_name
    dec si
    
    ; Copiar nome para temp_filename
    mov di, temp_filename
    xor cx, cx
.copy_temp:
    lodsb
    cmp al, 0
    je .temp_done
    cmp al, ' '
    je .temp_done
    stosb
    inc cx
    cmp cx, 31
    jae .temp_done
    jmp .copy_temp
.temp_done:
    xor al, al
    stosb
    
    ; Checar se já existe no diretório atual
    mov di, fs_storage
    mov cx, 20
.check_exists:
    push cx
    push di
    
    cmp byte [di], 0
    je .not_this_one
    
    ; Verificar se está no diretório atual
    call is_in_current_dir
    cmp ax, 0
    je .not_this_one
    
    ; Comparar nome (começa em di+1)
    push di
    inc di
    mov si, temp_filename
.cmp_name:
    lodsb
    cmp al, [di]
    jne .not_same
    inc di
    cmp al, 0
    je .already_exists
    jmp .cmp_name
    
.not_same:
    pop di
    
.not_this_one:
    pop di
    add di, 547
    pop cx
    loop .check_exists
    jmp .create
    
.already_exists:
    pop di
    pop di
    pop cx
    mov si, msg_already_exists
    call print_string
    ret
    
.create:
    mov di, fs_storage
    mov cx, 20
.find_slot:
    cmp byte [di], 0
    je .found_slot
    add di, 547
    loop .find_slot
    
    mov si, msg_fs_full
    call print_string
    ret
    
.found_slot:
    mov byte [di], 2
    inc di
    
    mov si, temp_filename
    mov cx, 32
    rep movsb
    
    ; Salvar o path completo
    mov si, current_dir
    mov cx, 32
    rep movsb
    
    mov si, msg_dir_created
    call print_string
    ret
    
.no_name:
    mov si, msg_no_name
    call print_string
    ret

handle_cd:
    call print_newline
    
    mov si, cmd_buffer
    add si, 3
    
.skip_space:
    lodsb
    cmp al, ' '
    je .skip_space
    dec si
    
    lodsb
    cmp al, 0
    je .show_current
    dec si
    
    ; Copiar nome do diretório
    mov di, temp_filename
    xor cx, cx
.copy_name:
    lodsb
    cmp al, 0
    je .name_done
    cmp al, ' '
    je .name_done
    stosb
    inc cx
    cmp cx, 31
    jae .name_done
    jmp .copy_name
.name_done:
    xor al, al
    stosb
    
    ; Verificar se o diretório existe no current_dir
    mov di, fs_storage
    mov cx, 20
    
.find_loop:
    push cx
    push di
    
    cmp byte [di], 2
    jne .next_dir
    
    ; Verificar se está no diretório atual
    call is_in_current_dir
    cmp ax, 0
    je .next_dir
    
    ; Comparar nome (começa em di+1)
    push di
    inc di
    mov si, temp_filename
.compare:
    lodsb
    cmp al, [di]
    jne .not_match
    inc di
    cmp al, 0
    je .found
    jmp .compare
    
.not_match:
    pop di
    
.next_dir:
    pop di
    add di, 547
    pop cx
    loop .find_loop
    
    mov si, msg_dir_not_found
    call print_string
    ret
    
.found:
    pop di
    pop di
    pop cx
    
    ; Construir novo path
    mov si, current_dir
    mov di, new_path
    
    ; Copiar current_dir
.copy_current:
    lodsb
    stosb
    cmp al, 0
    jne .copy_current
    dec di
    
    ; Adicionar / se não for raiz
    cmp byte [current_dir+1], 0
    je .skip_slash
    mov al, '/'
    stosb
.skip_slash:
    
    ; Adicionar nome do diretório
    mov si, temp_filename
.copy_new:
    lodsb
    stosb
    cmp al, 0
    jne .copy_new
    
    ; Copiar novo path para current_dir
    mov si, new_path
    mov di, current_dir
    mov cx, 32
    rep movsb
    
    ret
    
.show_current:
    mov si, current_dir
    call print_string
    ret

handle_rp:
    call print_newline
    mov byte [current_dir], '/'
    mov byte [current_dir+1], 0
    mov si, msg_root
    call print_string
    ret

handle_ls:
    call print_newline
    
    mov di, fs_storage
    mov cx, 20
    mov byte [found_any], 0
    
.loop:
    push cx
    
    cmp byte [di], 0
    je .next
    
    ; Verificar se está no diretório atual
    call is_in_current_dir
    cmp ax, 0
    je .next
    
    mov byte [found_any], 1
    
    ; O nome está em di+1
    push di
    inc di
    mov si, di
    call print_string
    pop di
    
    cmp byte [di], 2
    je .is_dir
    
    mov si, msg_file_type
    call print_string
    jmp .print_nl
    
.is_dir:
    mov si, msg_dir_type
    call print_string
    
.print_nl:
    call print_newline
    
.next:
    add di, 547
    pop cx
    loop .loop
    
    cmp byte [found_any], 0
    jne .done
    
    mov si, msg_empty_dir
    call print_string
    
.done:
    ret

handle_show:
    call print_newline
    
    mov si, cmd_buffer
    add si, 5
    
.skip_space:
    lodsb
    cmp al, ' '
    je .skip_space
    dec si
    
    lodsb
    cmp al, 0
    je .no_name
    dec si
    
    mov di, temp_filename
    mov cx, 32
.copy_name:
    lodsb
    cmp al, 0
    je .name_done
    cmp al, ' '
    je .name_done
    stosb
    loop .copy_name
.name_done:
    xor al, al
    stosb
    
    mov di, fs_storage
    mov cx, 20
    
.find_loop:
    push cx
    push di
    
    cmp byte [di], 1
    jne .next_file
    
    ; Verificar se está no diretório atual
    call is_in_current_dir
    cmp ax, 0
    je .next_file
    
    ; Comparar nome
    push di
    inc di
    mov si, temp_filename
.compare:
    lodsb
    cmp al, [di]
    jne .not_match
    inc di
    cmp al, 0
    je .found
    jmp .compare
    
.not_match:
    pop di
    
.next_file:
    pop di
    add di, 547
    pop cx
    loop .find_loop
    
    mov si, msg_not_found
    call print_string
    ret
    
.found:
    pop di
    pop di
    pop cx
    
    add di, 65
    
    mov cx, [di]
    add di, 2
    
    cmp cx, 0
    je .empty_file
    
    mov si, di
.print_loop:
    lodsb
    
    cmp al, 0x0D
    je .handle_cr
    cmp al, 0x0A
    je .handle_lf
    
    mov ah, 0x0E
    int 0x10
    
    dec cx
    cmp cx, 0
    jne .print_loop
    ret
    
.handle_cr:
    mov ah, 0x0E
    int 0x10
    dec cx
    cmp cx, 0
    jne .print_loop
    ret
    
.handle_lf:
    mov ah, 0x0E
    int 0x10
    dec cx
    cmp cx, 0
    jne .print_loop
    ret
    
.empty_file:
    mov si, msg_empty_file
    call print_string
    ret
    
.no_name:
    mov si, msg_no_name
    call print_string
    ret

handle_rm:
    call print_newline
    
    mov si, cmd_buffer
    add si, 3
    
.skip_space:
    lodsb
    cmp al, ' '
    je .skip_space
    dec si
    
    lodsb
    cmp al, 0
    je .no_name
    dec si
    
    ; Copiar nome
    mov di, temp_filename
    xor cx, cx
.copy_name:
    lodsb
    cmp al, 0
    je .name_done
    cmp al, ' '
    je .name_done
    stosb
    inc cx
    cmp cx, 31
    jae .name_done
    jmp .copy_name
.name_done:
    xor al, al
    stosb
    
    ; Procurar arquivo/pasta no diretório atual
    mov di, fs_storage
    mov cx, 20
    
.find_loop:
    push cx
    push di
    
    cmp byte [di], 0
    je .next_item
    
    ; Verificar se está no diretório atual
    call is_in_current_dir
    cmp ax, 0
    je .next_item
    
    ; Comparar nome
    push di
    inc di
    mov si, temp_filename
.compare:
    lodsb
    cmp al, [di]
    jne .not_match
    inc di
    cmp al, 0
    je .found
    jmp .compare
    
.not_match:
    pop di
    
.next_item:
    pop di
    add di, 547
    pop cx
    loop .find_loop
    
    mov si, msg_not_found
    call print_string
    ret
    
.found:
    pop di
    pop di
    pop cx
    
    ; Marcar como vazio (deletar)
    mov byte [di], 0
    
    mov si, msg_deleted
    call print_string
    ret
    
.no_name:
    mov si, msg_no_name
    call print_string
    ret

prompt_str: db 'BKSX$:', 0
prompt_end: db '> ', 0

cmd_help:   db 'help', 0
cmd_clear:  db 'clear', 0
cmd_echo:   db 'echo', 0
cmd_bae:    db 'bae', 0
cmd_mkdir:  db 'mkdir', 0
cmd_cd:     db 'cd', 0
cmd_rp:     db 'rp', 0
cmd_ls:     db 'ls', 0
cmd_show:   db 'show', 0
cmd_reboot: db 'reboot', 0
cmd_rm:     db 'rm', 0

msg_help:
    db 'Comandos:', 0x0D, 0x0A
    db ' help clear echo ls', 0x0D, 0x0A
    db ' bae <arquivo> - Editor', 0x0D, 0x0A
    db ' show <arquivo> - Ver conteudo', 0x0D, 0x0A
    db ' mkdir <dir> - Criar pasta', 0x0D, 0x0A
    db ' cd <dir> - Entrar pasta', 0x0D, 0x0A
    db ' rm <nome> - Remover arquivo/pasta', 0x0D, 0x0A
    db ' rp - Voltar raiz', 0x0D, 0x0A
    db ' reboot - Reiniciar', 0

msg_unknown: db 'Comando invalido', 0
msg_reboot: db 'Reiniciando...', 0
msg_editor_help: db 'Editor BAE - Ctrl+S=Salvar Ctrl+C=Sair', 0
msg_saved: db 'Arquivo salvo!', 0
msg_no_name: db 'Especifique um nome', 0
msg_fs_full: db 'Sistema de arquivos cheio', 0
msg_dir_created: db 'Pasta criada', 0
msg_root: db 'Voltou para raiz', 0
msg_file_type: db ' [arquivo]', 0
msg_dir_type: db ' [pasta]', 0
msg_not_found: db 'Arquivo nao encontrado', 0
msg_empty_file: db '(arquivo vazio)', 0
msg_dir_not_found: db 'Pasta nao encontrada', 0
msg_already_exists: db 'Ja existe com esse nome', 0
msg_empty_dir: db '(vazio)', 0
msg_deleted: db 'Removido com sucesso', 0

current_dir: times 33 db 0
temp_filename: times 33 db 0
new_path: times 33 db 0
cmd_buffer: times 128 db 0
editor_buffer: times 2048 db 0
editor_size: dw 0
found_any: db 0

fs_storage: times 10940 db 0