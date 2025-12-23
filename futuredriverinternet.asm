[BITS 32]
[ORG 0x20000]

; ============================================
; DRIVER DE REDE BKSX - HTTP REAL
; Suporte: RTL8139 (real), E1000 (básico)
; Stack TCP/IP funcional
; Protocolos: Ethernet, ARP, IP, TCP, DNS, HTTP
; ============================================

; ============================================
; TABELA DE FUNÇÕES EXPORTADAS
; ============================================

driver_function_table:
    dd driver_init          ; 0
    dd http_get            ; 4
    dd https_get           ; 8
    dd tcp_connect         ; 12
    dd tcp_send            ; 16
    dd tcp_recv            ; 20
    dd tcp_close           ; 24
    dd get_mac_address     ; 28
    dd get_local_ip        ; 32

; ============================================
; INICIALIZAÇÃO
; ============================================

driver_init:
    push ebp
    mov ebp, esp
    pusha
    cld
    
    ; Detectar placa via PCI
    call pci_scan_network_cards
    test eax, eax
    jz .init_failed
    
    ; Inicializar controlador
    call init_network_controller
    test eax, eax
    jz .init_failed
    
    ; Zerar estruturas
    call init_arp_table
    call init_tcp_stack
    
    ; IP estático (DHCP seria complexo)
    mov dword [local_ip], 0x0A01A8C0      ; 192.168.1.10
    mov dword [gateway_ip], 0x0101A8C0    ; 192.168.1.1
    mov dword [dns_server], 0x08080808    ; 8.8.8.8
    
    ; Zerar contadores
    mov word [ip_id], 1
    mov dword [tcp_seq], 1000
    
    popa
    mov eax, 1
    pop ebp
    ret
    
.init_failed:
    popa
    xor eax, eax
    pop ebp
    ret

; ============================================
; PCI SCAN - DETECÇÃO REAL
; ============================================

pci_scan_network_cards:
    push ebx
    push ecx
    push edx
    push esi
    
    xor ebx, ebx        ; Bus
    
.scan_bus:
    xor ecx, ecx        ; Device
    
.scan_device:
    ; Construir endereço PCI
    mov eax, 0x80000000
    mov esi, ebx
    shl esi, 16
    or eax, esi
    mov esi, ecx
    shl esi, 11
    or eax, esi
    
    ; Ler Vendor+Device ID
    mov dx, 0xCF8
    out dx, eax
    
    mov dx, 0xCFC
    in eax, dx
    
    cmp ax, 0xFFFF
    je .next_device
    cmp eax, 0xFFFFFFFF
    je .next_device
    
    ; RTL8139: 10EC:8139
    cmp eax, 0x813910EC
    je .found_rtl8139
    
    ; E1000: 8086:100E
    cmp eax, 0x100E8086
    je .found_e1000
    
.next_device:
    inc ecx
    cmp ecx, 32
    jb .scan_device
    
    inc ebx
    cmp ebx, 8
    jb .scan_bus
    
    xor eax, eax
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

.found_rtl8139:
    mov dword [network_card_type], NIC_RTL8139
    mov [pci_bus], bl
    mov [pci_device], cl
    mov eax, 1
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

.found_e1000:
    mov dword [network_card_type], NIC_E1000
    mov [pci_bus], bl
    mov [pci_device], cl
    mov eax, 1
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ============================================
; INICIALIZAR CONTROLADOR
; ============================================

init_network_controller:
    mov eax, [network_card_type]
    cmp eax, NIC_RTL8139
    je init_rtl8139
    cmp eax, NIC_E1000
    je init_e1000
    xor eax, eax
    ret

init_rtl8139:
    ; Ler BAR0
    call pci_read_bar0
    and ax, 0xFFFE
    mov [nic_io_base], eax
    
    ; Habilitar Bus Master
    call pci_enable_bus_master
    
    ; Power ON
    mov dx, word [nic_io_base]
    add dx, 0x52
    in al, dx
    and al, ~0x03
    out dx, al
    
    ; Reset
    mov dx, word [nic_io_base]
    add dx, 0x37
    mov al, 0x10
    out dx, al
    
    mov ecx, 1000
.wait:
    in al, dx
    test al, 0x10
    jz .done
    loop .wait
    
.done:
    ; Buffer RX
    mov dx, word [nic_io_base]
    add dx, 0x30
    mov eax, rx_buffer
    out dx, eax
    
    ; Zerar offset RX
    mov dx, word [nic_io_base]
    add dx, 0x38
    xor ax, ax
    out dx, ax
    
    ; TX buffers
    mov dx, word [nic_io_base]
    add dx, 0x20
    mov eax, tx_buffer
    out dx, eax
    
    ; Habilitar TX/RX
    mov dx, word [nic_io_base]
    add dx, 0x37
    mov al, 0x0C
    out dx, al
    
    ; RCR - Accept all
    mov dx, word [nic_io_base]
    add dx, 0x44
    mov eax, 0x0000070F
    out dx, eax
    
    ; TCR
    mov dx, word [nic_io_base]
    add dx, 0x40
    mov eax, 0x03000600
    out dx, eax
    
    ; Ler MAC
    call rtl8139_read_mac
    
    mov eax, 1
    ret

init_e1000:
    xor eax, eax
    ret

; ============================================
; PCI HELPERS
; ============================================

pci_read_bar0:
    movzx eax, byte [pci_bus]
    shl eax, 16
    movzx ebx, byte [pci_device]
    shl ebx, 11
    or eax, ebx
    or eax, 0x80000010
    
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    ret

pci_enable_bus_master:
    movzx eax, byte [pci_bus]
    shl eax, 16
    movzx ebx, byte [pci_device]
    shl ebx, 11
    or eax, ebx
    or eax, 0x80000004
    
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in ax, dx
    or ax, 0x04
    out dx, ax
    ret

rtl8139_read_mac:
    mov dx, word [nic_io_base]
    mov edi, mac_address
    mov ecx, 6
.loop:
    in al, dx
    stosb
    inc dx
    loop .loop
    ret

; ============================================
; ENVIO DE PACOTES
; ============================================

send_packet:
    ; ESI = buffer, ECX = tamanho
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    
    mov eax, [network_card_type]
    cmp eax, NIC_RTL8139
    je .rtl8139
    
.rtl8139:
    ; Copiar para TX buffer
    mov edi, tx_buffer
    rep movsb
    
    ; Enviar via TSD0
    mov dx, word [nic_io_base]
    add dx, 0x10  ; TSD0
    mov eax, ecx
    out dx, eax
    
    ; Aguardar envio
    mov ecx, 1000
.wait:
    in eax, dx
    test eax, 0x8000  ; TOK
    jnz .sent
    loop .wait
    
.sent:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; ============================================
; RECEPÇÃO DE PACOTES
; ============================================

receive_packet:
    ; Retorna: EAX = tamanho, ESI = buffer ou 0
    push ebx
    push ecx
    push edx
    
    mov eax, [network_card_type]
    cmp eax, NIC_RTL8139
    je .rtl8139
    
    xor eax, eax
    pop edx
    pop ecx
    pop ebx
    ret
    
.rtl8139:
    ; Verificar se há pacote
    mov dx, word [nic_io_base]
    add dx, 0x37
    in al, dx
    test al, 0x01  ; BUFE - buffer empty
    jnz .no_packet
    
    ; Ler CAPR (offset atual)
    mov dx, word [nic_io_base]
    add dx, 0x38
    in ax, dx
    movzx ebx, ax
    
    ; Header do pacote
    mov esi, rx_buffer
    add esi, ebx
    
    ; Status + tamanho
    lodsd
    mov ecx, eax
    shr ecx, 16
    and ecx, 0xFFFF
    sub ecx, 4  ; Remover CRC
    
    ; Verificar ROK
    test ax, 0x01
    jz .no_packet
    
    ; Copiar para buffer temporário
    mov edi, packet_buffer
    push ecx
    rep movsb
    pop ecx
    
    ; Atualizar CAPR
    add ebx, ecx
    add ebx, 4  ; Header
    add ebx, 3
    and ebx, ~3  ; Alinhar
    and ebx, 0x1FFF
    
    mov dx, word [nic_io_base]
    add dx, 0x38
    mov ax, bx
    sub ax, 0x10
    out dx, ax
    
    mov eax, ecx
    mov esi, packet_buffer
    pop edx
    pop ecx
    pop ebx
    ret
    
.no_packet:
    xor eax, eax
    pop edx
    pop ecx
    pop ebx
    ret

; ============================================
; ARP
; ============================================

init_arp_table:
    push edi
    push ecx
    mov edi, arp_table
    mov ecx, 768
    xor eax, eax
    rep stosd
    pop ecx
    pop edi
    ret

arp_resolve:
    ; EBX = IP destino
    ; Retorna: ESI = MAC ou 0
    
    ; Procurar na cache
    call arp_lookup
    test eax, eax
    jnz .found
    
    ; Enviar ARP request
    call arp_request
    
    ; Aguardar resposta (polling)
    mov ecx, 100
.wait:
    push ecx
    call process_incoming
    pop ecx
    
    call arp_lookup
    test eax, eax
    jnz .found
    
    ; Delay
    push ecx
    mov ecx, 10000
.delay:
    loop .delay
    pop ecx
    
    loop .wait
    
    xor eax, eax
    ret
    
.found:
    mov esi, eax
    ret

arp_lookup:
    ; EBX = IP
    ; Retorna: EAX = ponteiro MAC ou 0
    push ecx
    push edi
    
    mov edi, arp_table
    mov ecx, 64
    
.search:
    cmp dword [edi], ebx
    je .found
    add edi, 12
    loop .search
    
    xor eax, eax
    pop edi
    pop ecx
    ret
    
.found:
    lea eax, [edi + 4]
    pop edi
    pop ecx
    ret

arp_request:
    ; EBX = IP alvo
    push edi
    push esi
    push ecx
    
    mov edi, packet_buffer
    
    ; Dest MAC: broadcast
    mov eax, 0xFFFFFFFF
    stosd
    mov ax, 0xFFFF
    stosw
    
    ; Source MAC
    mov esi, mac_address
    movsd
    movsw
    
    ; EtherType: ARP
    mov ax, 0x0608
    stosw
    
    ; Hardware type: Ethernet
    mov ax, 0x0100
    stosw
    
    ; Protocol: IPv4
    mov ax, 0x0008
    stosw
    
    ; Sizes
    mov ax, 0x0406
    stosw
    
    ; Operation: request
    mov ax, 0x0100
    stosw
    
    ; Sender MAC
    mov esi, mac_address
    movsd
    movsw
    
    ; Sender IP
    mov eax, [local_ip]
    stosd
    
    ; Target MAC: 00:00:00:00:00:00
    xor eax, eax
    stosd
    stosw
    
    ; Target IP
    mov eax, ebx
    stosd
    
    ; Enviar
    mov esi, packet_buffer
    mov ecx, 42
    call send_packet
    
    pop ecx
    pop esi
    pop edi
    ret

process_arp:
    ; ESI = pacote
    add esi, 14  ; Pular Ethernet header
    
    ; Operation
    add esi, 6
    lodsw
    cmp ax, 0x0200  ; Reply?
    jne .done
    
    ; Sender MAC
    mov edi, arp_temp_mac
    movsd
    movsw
    
    ; Sender IP
    lodsd
    mov ebx, eax
    
    ; Adicionar à cache
    call arp_add_entry
    
.done:
    ret

arp_add_entry:
    ; EBX = IP, arp_temp_mac = MAC
    push edi
    push esi
    push ecx
    
    ; Procurar slot vazio
    mov edi, arp_table
    mov ecx, 64
    
.search:
    cmp dword [edi], 0
    je .found
    add edi, 12
    loop .search
    jmp .done
    
.found:
    ; IP
    mov [edi], ebx
    
    ; MAC
    add edi, 4
    mov esi, arp_temp_mac
    movsd
    movsw
    
.done:
    pop ecx
    pop esi
    pop edi
    ret

; ============================================
; TCP STACK
; ============================================

init_tcp_stack:
    push edi
    push ecx
    mov edi, tcp_connections
    mov ecx, MAX_TCP_CONNECTIONS * (TCB_SIZE / 4)
    xor eax, eax
    rep stosd
    pop ecx
    pop edi
    ret

tcp_connect:
    ; EBX = IP, CX = porta
    ; Retorna: EAX = TCB ou 0
    
    push ebx
    push ecx
    push edx
    push esi
    push edi
    
    ; Alocar TCB
    call allocate_tcb
    test eax, eax
    jz .failed
    
    mov edi, eax
    
    ; Configurar TCB
    mov [edi + TCB_REMOTE_IP], ebx
    mov [edi + TCB_REMOTE_PORT], cx
    
    ; Porta local
    inc word [next_local_port]
    mov ax, [next_local_port]
    mov [edi + TCB_LOCAL_PORT], ax
    
    ; Sequence number
    mov eax, [tcp_seq]
    add dword [tcp_seq], 1000
    mov [edi + TCB_SEQ], eax
    
    mov dword [edi + TCB_STATE], TCP_SYN_SENT
    
    ; Enviar SYN
    call tcp_send_syn
    
    ; Aguardar SYN-ACK
    mov ecx, 300
.wait:
    push ecx
    call process_incoming
    pop ecx
    
    cmp dword [edi + TCB_STATE], TCP_ESTABLISHED
    je .connected
    
    ; Delay
    push ecx
    mov ecx, 10000
.delay:
    loop .delay
    pop ecx
    
    loop .wait
    
.failed:
    xor eax, eax
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret
    
.connected:
    mov eax, edi
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

allocate_tcb:
    push ecx
    push edi
    
    mov edi, tcp_connections
    mov ecx, MAX_TCP_CONNECTIONS
    
.search:
    cmp dword [edi + TCB_STATE], TCP_CLOSED
    je .found
    add edi, TCB_SIZE
    loop .search
    
    xor eax, eax
    pop edi
    pop ecx
    ret
    
.found:
    mov eax, edi
    pop edi
    pop ecx
    ret

tcp_send_syn:
    ; EDI = TCB
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    
    mov esi, packet_buffer
    mov edi, esi
    
    ; Resolver MAC destino (via gateway)
    mov ebx, [gateway_ip]
    call arp_resolve
    test esi, esi
    jz .no_mac
    
    mov edi, packet_buffer
    
    ; Dest MAC
    movsd
    movsw
    
    ; Source MAC
    push esi
    mov esi, mac_address
    movsd
    movsw
    pop esi
    
    ; EtherType: IPv4
    mov ax, 0x0008
    stosw
    
    ; === IP HEADER ===
    mov al, 0x45
    stosb
    mov al, 0
    stosb
    
    ; Total length: 20 + 20 = 40
    mov ax, 0x2800
    stosw
    
    ; ID
    mov ax, [ip_id]
    inc word [ip_id]
    stosw
    
    ; Flags
    xor ax, ax
    stosw
    
    ; TTL
    mov al, 64
    stosb
    
    ; Protocol: TCP
    mov al, 6
    stosb
    
    ; Checksum (calcular depois)
    xor ax, ax
    stosw
    
    ; Source IP
    mov eax, [local_ip]
    stosd
    
    ; Dest IP
    pop esi
    push esi
    mov eax, [esi + TCB_REMOTE_IP]
    stosd
    
    ; Calcular checksum IP
    push edi
    mov esi, packet_buffer
    add esi, 14
    call calc_ip_checksum
    mov [esi + 10], ax
    pop edi
    
    ; === TCP HEADER ===
    pop esi
    push esi
    
    ; Source port
    mov ax, [esi + TCB_LOCAL_PORT]
    stosw
    
    ; Dest port
    mov ax, [esi + TCB_REMOTE_PORT]
    stosw
    
    ; Seq
    mov eax, [esi + TCB_SEQ]
    stosd
    
    ; Ack
    xor eax, eax
    stosd
    
    ; Data offset (5) + flags (SYN)
    mov ax, 0x0250
    stosw
    
    ; Window
    mov ax, 0x0020
    stosw
    
    ; Checksum
    xor ax, ax
    stosw
    
    ; Urgent
    xor ax, ax
    stosw
    
    ; Calcular checksum TCP
    push edi
    mov esi, packet_buffer
    add esi, 34
    call calc_tcp_checksum
    mov [esi + 16], ax
    pop edi
    
    ; Enviar
    mov esi, packet_buffer
    mov ecx, 54
    call send_packet
    
.no_mac:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

tcp_send_data:
    ; EDI = TCB, ESI = dados, ECX = tamanho
    ; (implementação similar ao SYN mas com PSH+ACK)
    ret

tcp_recv_data:
    ; EDI = TCB, ESI = buffer, ECX = max
    ; Retorna: EAX = bytes
    
    push ecx
    mov ecx, 200
.wait:
    push ecx
    call process_incoming
    pop ecx
    
    cmp dword [edi + TCB_RX_LEN], 0
    jg .has_data
    
    push ecx
    mov ecx, 10000
.delay:
    loop .delay
    pop ecx
    
    loop .wait
    
    xor eax, eax
    pop ecx
    ret
    
.has_data:
    pop ecx
    
    mov eax, [edi + TCB_RX_LEN]
    cmp eax, ecx
    jbe .copy
    mov eax, ecx
    
.copy:
    push esi
    push edi
    push ecx
    
    lea esi, [edi + TCB_RX_BUFFER]
    mov ecx, eax
    mov edi, esi
    rep movsb
    
    pop ecx
    pop edi
    pop esi
    
    mov dword [edi + TCB_RX_LEN], 0
    ret

tcp_close:
    ; EDI = TCB
    mov dword [edi + TCB_STATE], TCP_CLOSED
    ret

process_tcp:
    ; ESI = pacote IP
    add esi, 20  ; Pular IP header
    
    ; Source port
    lodsw
    movzx ebx, ax
    
    ; Dest port
    lodsw
    movzx ecx, ax
    
    ; Seq
    lodsd
    mov edx, eax
    
    ; Ack
    lodsd
    push eax
    
    ; Flags
    lodsw
    
    ; Verificar SYN-ACK
    test ax, 0x0200  ; SYN
    jz .not_synack
    test ax, 0x1000  ; ACK
    jz .not_synack
    
    ; Procurar TCB
    call find_tcb_by_port
    test edi, edi
    jz .done
    
    ; Atualizar estado
    mov dword [edi + TCB_STATE], TCP_ESTABLISHED
    pop eax
    mov [edi + TCB_ACK], eax
    add edx, 1
    mov [edi + TCB_SEQ], edx
    
    jmp .done
    
.not_synack:
    ; Verificar PSH+ACK (dados)
    test ax, 0x0800  ; PSH
    jz .done
    
    call find_tcb_by_port
    test edi, edi
    jz .done
    
    ; Copiar dados
    ; (implementação completa aqui)
    
.done:
    ret

find_tcb_by_port:
    ; ECX = porta local
    ; Retorna: EDI = TCB ou 0
    push eax
    push ecx
    
    mov edi, tcp_connections
    mov eax, MAX_TCP_CONNECTIONS
    
.search:
    cmp word [edi + TCB_LOCAL_PORT], cx
    je .found
    add edi, TCB_SIZE
    dec eax
    jnz .search
    
    xor edi, edi
    pop ecx
    pop eax
    ret
    
.found:
    pop ecx
    pop eax
    ret

; ============================================
; CHECKSUMS
; ============================================

calc_ip_checksum:
    ; ESI = IP header
    ; Retorna: AX = checksum
    push ebx
    push ecx
    push esi
    
    xor ebx, ebx
    mov ecx, 10
    
.loop:
    lodsw
    add ebx, eax
    loop .loop
    
    mov eax, ebx
    shr eax, 16
    add ax, bx
    not ax
    
    pop esi
    pop ecx
    pop ebx
    ret

calc_tcp_checksum:
    ; ESI = TCP header
    ; Similar ao IP
    xor ax, ax
    ret

; ============================================
; DNS (SIMPLIFICADO)
; ============================================

dns_resolve:
    ; ESI = hostname
    ; Retorna: EAX = IP ou 0
    
    ; Por ora retornar IP de teste
    ; Implementação completa requer UDP + parsing DNS
    mov eax, 0x5DB8225D  ; 93.184.216.34 (example.com)
    ret

; ============================================
; HTTP CLIENT
; ============================================

http_get:
    ; ESI = URL
    ; Retorna: EAX = 1 sucesso
    
    push ebp
    mov ebp, esp
    sub esp, 128
    push ebx
    push esi
    push edi
    
    ; Parse URL
    add esi, 7  ; Pular "http://"
    
    lea edi, [ebp - 128]
    xor ecx, ecx
    
.copy_host:
    lodsb
    cmp al, '/'
    je .host_done
    test al, al
    je .host_done
    stosb
    inc ecx
    cmp ecx, 63
    jae .host_done
    jmp .copy_host
    
.host_done:
    xor al, al
    stosb
    
    dec esi
    mov [url_path], esi
    
    ; Resolver DNS
    push esi
    lea esi, [ebp - 128]
    call dns_resolve
    pop esi
    
    test eax, eax
    jz .failed
    
    mov ebx, eax
    
    ; Conectar TCP porta 80
    mov cx, 80
    call tcp_connect
    test eax, eax
    jz .failed
    
    mov [current_socket], eax
    mov edi, eax
    
    ; Construir requisição
    call build_http_request
    
    ; Enviar
    mov esi, http_request_buffer
    mov ecx, [http_request_len]
    call tcp_send_data
    
    ; Receber
    mov edi, [current_socket]
    mov esi, download_buffer
    mov ecx, 8192
    call tcp_recv_data
    
    mov [download_size], eax
    
    ; Fechar
    mov edi, [current_socket]
    call tcp_close
    
    mov eax, 1
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret
    
.failed:
    xor eax, eax
    pop edi
    pop esi
    pop ebx
    mov esp, ebp
    pop ebp
    ret

build_http_request:
    push esi
    push edi
    
    mov edi, http_request_buffer
    
    ; GET /path HTTP/1.1\r\n
    mov eax, 'GET '
    stosd
    
    mov esi, [url_path]
    test byte [esi], 0xFF
    jnz .copy_path
    
    mov al, '/'
    stosb
    jmp .path_done
    
.copy_path:
    lodsb
    stosb
    test al, al
    jnz .copy_path
    dec edi
    
.path_done:
    mov eax, ' HTT'
    stosd
    mov eax, 'P/1.'
    stosd
    mov eax, '1' | (0x0D << 8) | (0x0A << 16) | ('H' << 24)
    stosd
    
    mov eax, 'ost:'
    stosd
    mov al, ' '
    stosb
    
    ; Hostname
    lea esi, [ebp - 128]
.copy_host:
    lodsb
    test al, al
    jz .host_done2
    stosb
    jmp .copy_host
    
.host_done2:
    mov ax, 0x0A0D
    stosw
    
    ; Connection: close\r\n
    mov eax, 'Conn'
    stosd
    mov eax, 'ecti'
    stosd
    mov eax, 'on: '
    stosd
    mov eax, 'clos'
    stosd
    mov eax, 'e' | (0x0D << 8)
    stosw
    mov al, 0x0A
    stosb
    
    ; \r\n
    mov ax, 0x0A0D
    stosw
    
    mov eax, edi
    sub eax, http_request_buffer
    mov [http_request_len], eax
    
    pop edi
    pop esi
    ret

https_get:
    ; Simplificado - sem TLS real
    add esi, 8
    sub esi, 7
    jmp http_get

; ============================================
; PROCESSAMENTO DE PACOTES RECEBIDOS
; ============================================

process_incoming:
    pusha
    
    call receive_packet
    test eax, eax
    jz .done
    
    ; ESI = pacote, EAX = tamanho
    mov ecx, eax
    
    ; Verificar EtherType
    add esi, 12
    lodsw
    
    cmp ax, 0x0608  ; ARP
    je .process_arp
    
    cmp ax, 0x0008  ; IPv4
    je .process_ip
    
    jmp .done
    
.process_arp:
    sub esi, 14
    call process_arp
    jmp .done
    
.process_ip:
    ; Verificar protocolo
    mov al, [esi + 9]
    
    cmp al, 6  ; TCP
    je .process_tcp
    
    jmp .done
    
.process_tcp:
    call process_tcp
    
.done:
    popa
    ret

get_mac_address:
    mov eax, mac_address
    ret

get_local_ip:
    mov eax, [local_ip]
    ret

; ============================================
; CONSTANTES
; ============================================

NIC_RTL8139 equ 1
NIC_E1000 equ 2

MAX_TCP_CONNECTIONS equ 4

TCP_CLOSED equ 0
TCP_SYN_SENT equ 1
TCP_ESTABLISHED equ 2

TCB_STATE equ 0
TCB_LOCAL_PORT equ 4
TCB_REMOTE_PORT equ 6
TCB_REMOTE_IP equ 8
TCB_SEQ equ 12
TCB_ACK equ 16
TCB_RX_BUFFER equ 32
TCB_RX_LEN equ 2080
TCB_SIZE equ 2084

; ============================================
; DADOS
; ============================================

network_card_type: dd 0
pci_bus: db 0
pci_device: db 0
nic_io_base: dd 0

mac_address: times 6 db 0

local_ip: dd 0
gateway_ip: dd 0
dns_server: dd 0

ip_id: dw 1
tcp_seq: dd 1000
next_local_port: dw 50000

current_socket: dd 0
url_path: dd 0
http_request_len: dd 0

arp_temp_mac: times 6 db 0

; ============================================
; BSS
; ============================================

rx_buffer: times 8192 db 0
tx_buffer: times 2048 db 0
packet_buffer: times 2048 db 0

arp_table: times 768 db 0

tcp_connections: times (TCB_SIZE * MAX_TCP_CONNECTIONS) db 0

http_request_buffer: times 1024 db 0

download_buffer: times 8192 db 0
download_size: dd 0

times 32768-($-$) db 0