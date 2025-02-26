#!/bin/bash
#=====================================================
# 1. FUNCIONES GENERALES
#=====================================================

# Función para obtener la IP del equipo
get_ip_address() {
    ip -o -4 addr show | tr -s ' ' | grep -Ev ' lo|docker' | awk '{print $2 ":", $4}' | cut -d/ -f1
}

# Función para ver si dnsmasq está instalado vía APT
check_dnsmasq_system() {
    if ! dpkg -l | grep -qw dnsmasq || ! systemctl list-unit-files | grep -q "dnsmasq.service"; then
        return 1
    fi
    if [[ -f /etc/dnsmasq.conf ]] && grep -q "Ansible managed" /etc/dnsmasq.conf; then
        return 1
    fi
    return 0
}

# Función para verificar el estado de dnsmasq en Docker
check_dnsmasq_docker() {
    CONTAINER_RUNNING=$(docker ps -q --filter "ancestor=diego57709/dnsmasq")
    CONTAINER_EXISTS=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
    IMAGE_EXISTS=$(docker images -q "diego57709/dnsmasq")
    if [[ -n "$CONTAINER_RUNNING" ]]; then
        return 0 
    elif [[ -n "$CONTAINER_EXISTS" ]]; then
        return 2
    elif [[ -n "$IMAGE_EXISTS" ]]; then
        return 3
    else
        return 1
    fi
}

# Función para verificar si dnsmasq fue instalado con Ansible
check_dnsmasq_ansible() {
    if ! command -v ansible &>/dev/null; then
        return 1
    fi
    if ! dpkg -l | grep -qw dnsmasq; then
        return 1
    fi
    if [[ -f /etc/dnsmasq.conf ]] && grep -q "Ansible managed" /etc/dnsmasq.conf; then
        return 0
    else
        return 1
    fi
}

# Función para ver si se está usando un puerto
check_port() {
    local port=$1
    if ss -tuln | grep -E -q ":${port}($|[^0-9])"; then
        return 0
    else
        return 1
    fi
}

# Función para resolver conflicto de puerto
resolve_port_conflict() {
    local current_port=$1
    local new_port
    while true; do
        read -p "El puerto $current_port está en uso. Ingrese un nuevo puerto: " new_port
        if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then
            echo "Error: Debe ingresar un número de puerto válido." >&2
            continue
        fi
        if ! check_port "$new_port"; then
            echo "$new_port"
            return
        else
            echo "El puerto $new_port también está en uso. Intente con otro." >&2
        fi
    done
}

# Función para instalar Docker
instalar_docker() {
    echo "Verificando si Docker está instalado..."
    if command -v docker &> /dev/null; then
        echo "Docker ya está instalado."
    else
        echo "Instalando Docker..."
        sudo apt update
        sudo apt install -y ca-certificates curl gnupg lsb-release
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl enable docker
        sudo systemctl start docker
        echo "Docker instalado correctamente."
    fi
    if groups $USER | grep -q "\bdocker\b"; then
        echo "El usuario $USER ya tiene permisos para Docker."
    else
        echo "Añadiendo el usuario $USER al grupo docker..."
        sudo groupadd docker 2>/dev/null 
        sudo usermod -aG docker $USER
        echo "El usuario $USER ha sido añadido al grupo docker. Es recomendable reiniciar el sistema."
    fi
}

#=====================================================
# 2. GESTIÓN DE ANSIBLE REMOTO (sin localhost)
#=====================================================

ANSIBLE_REMOTE_FILE="$HOME/.ansible_remote"
ANSIBLE_REMOTE=""

# Función para configurar la máquina remota para Ansible
configurar_ansible_remote() {
    read -p "Ingrese la IP o hostname de la máquina remota donde se gestionará Ansible: " remote_ansible
    if [[ -z "$remote_ansible" ]]; then
        echo "Error: Debe ingresar una máquina remota."
        exit 1
    fi
    echo "$remote_ansible" > "$ANSIBLE_REMOTE_FILE"
    ANSIBLE_REMOTE="$remote_ansible"
    echo "Máquina remota configurada: $ANSIBLE_REMOTE"
}

# Función para instalar Ansible en la máquina remota usando sudo -S
instalar_ansible() {
    if [[ -f "$ANSIBLE_REMOTE_FILE" ]]; then
        ANSIBLE_REMOTE=$(cat "$ANSIBLE_REMOTE_FILE")
        echo "Usando máquina remota para Ansible: $ANSIBLE_REMOTE"
    else
        read -p "No se ha configurado una máquina remota para Ansible. ¿Desea configurarla ahora? (s/n): " resp
        if [[ "$resp" == "s" || "$resp" == "S" ]]; then
            configurar_ansible_remote
        else
            echo "Debe configurar una máquina remota. Saliendo..."
            exit 1
        fi
    fi

    if [[ "$ANSIBLE_REMOTE" == "localhost" ]]; then
        echo "Error: Se requiere una máquina remota. No se puede usar 'localhost'."
        exit 1
    fi

    if [[ -z "$REMOTE_SUDO_PASS" ]]; then
        read -s -p "Ingrese la contraseña sudo para $ANSIBLE_REMOTE: " REMOTE_SUDO_PASS
        echo ""
    fi

    if ! ssh "$ANSIBLE_REMOTE" 'command -v ansible' &>/dev/null; then
        echo "Ansible no está instalado en $ANSIBLE_REMOTE. Instalándolo vía SSH..."
        ssh "$ANSIBLE_REMOTE" "echo '$REMOTE_SUDO_PASS' | sudo -S apt update && echo '$REMOTE_SUDO_PASS' | sudo -S apt install -y ansible"
    else
        echo "Ansible ya está instalado en $ANSIBLE_REMOTE."
    fi
}

# Función para generar un inventario dinámico para Ansible (solo remoto)
generar_inventario_ansible() {
    INVENTORY_FILE="/tmp/ansible_hosts"
    if [[ "$ANSIBLE_REMOTE" == "localhost" ]]; then
        echo "Error: La máquina remota no puede ser 'localhost'."
        exit 1
    else
        echo -e "[remote]\n$ANSIBLE_REMOTE ansible_user=$(whoami) ansible_connection=ssh" > "$INVENTORY_FILE"
    fi
}

#=====================================================
# 3. ESTADO DEL SISTEMA
#=====================================================

estadoSistema() {
    echo "-----------------------------------------------------"
    echo " Estado actual del sistema"
    echo "-----------------------------------------------------"
    echo -e "IP del equipo local: \n$(get_ip_address)"
    if [[ $ANSIBLE_STATUS -eq 0 ]]; then
        echo "dnsmasq fue instalado con Ansible en $ANSIBLE_REMOTE."
        estadoSistemaAnsible
    elif [[ $SYSTEM_STATUS -eq 0 ]]; then
        echo "dnsmasq está instalado por APT."
        if [[ -f /etc/dnsmasq.conf ]]; then
            interfaz=$(grep "^interface=" /etc/dnsmasq.conf | cut -d'=' -f2)
            puerto=$(grep "^port=" /etc/dnsmasq.conf | cut -d'=' -f2)
            ip=$(ip -o -4 addr show "$interfaz" | awk '{print $4}' | cut -d/ -f1)
            echo "Interfaz: $interfaz | IP: $ip | Puerto: $puerto"
        fi
    elif [[ $DOCKER_STATUS -eq 0 ]]; then
        echo "dnsmasq está corriendo en un contenedor Docker."
        CONFIG_FILE=~/dnsmasq-docker/dnsmasq.conf
        if [[ -f "$CONFIG_FILE" ]]; then
            interfaz=$(grep "^interface=" "$CONFIG_FILE" | cut -d'=' -f2)
            puerto=$(grep "^port=" "$CONFIG_FILE" | cut -d'=' -f2)
            ip=$(ip -o -4 addr show "$interfaz" | awk '{print $4}' | cut -d/ -f1)
            echo "Interfaz (Docker): $interfaz | IP: $ip | Puerto: $puerto"
        fi
    elif [[ $DOCKER_STATUS -eq 2 ]]; then
        echo "dnsmasq está en Docker pero el contenedor está detenido."
    elif [[ $DOCKER_STATUS -eq 3 ]]; then
        echo "dnsmasq está en Docker como imagen, pero no hay contenedor creado."
    else
        echo "dnsmasq NO está instalado en el sistema, Docker ni gestionado por Ansible."
    fi
}

estadoSistemaAnsible() {
    generar_inventario_ansible
    cat <<'EOF' > /tmp/estado_ansible.yml
---
- name: Obtener estado de dnsmasq en host remoto
  hosts: remote
  gather_facts: no
  become: yes
  tasks:
    - name: Obtener puerto configurado en /etc/dnsmasq.conf
      shell: "grep '^port=' /etc/dnsmasq.conf | cut -d'=' -f2"
      register: dnsmasq_port
      changed_when: false
    - name: Obtener interfaz configurada en /etc/dnsmasq.conf
      shell: "grep '^interface=' /etc/dnsmasq.conf | cut -d'=' -f2"
      register: dnsmasq_iface
      changed_when: false
    - name: Obtener IP de la interfaz configurada
      shell: "ip -o -4 addr show {{ dnsmasq_iface.stdout }} | awk '{print \$4}' | cut -d/ -f1"
      register: iface_ip
      changed_when: false
    - name: Mostrar información de dnsmasq
      debug:
        msg: "Interfaz: {{ dnsmasq_iface.stdout }}, IP: {{ iface_ip.stdout }}, Puerto: {{ dnsmasq_port.stdout }}"
EOF
    echo "Ejecutando playbook para obtener estado de dnsmasq en $ANSIBLE_REMOTE..."
    ansible-playbook -i "$INVENTORY_FILE" /tmp/estado_ansible.yml
}

#=====================================================
# 4. INSTALACIÓN DE DNSMASQ
#=====================================================

verificar_instalacion_existente() {
    check_dnsmasq_system
    SYSTEM_STATUS=$?
    check_dnsmasq_docker
    DOCKER_STATUS=$?
    check_dnsmasq_ansible
    ANSIBLE_STATUS=$?
    if [[ $SYSTEM_STATUS -eq 0 ]]; then
        echo "ERROR! dnsmasq ya está instalado en el sistema (APT)."
        return 1
    elif [[ $DOCKER_STATUS -eq 0 || $DOCKER_STATUS -eq 2 || $DOCKER_STATUS -eq 3 ]]; then
        echo "ERROR! dnsmasq ya está instalado o disponible en Docker."
        return 1
    elif [[ $ANSIBLE_STATUS -eq 0 ]]; then
        echo "ERROR! dnsmasq ya fue instalado con Ansible."
        return 1
    fi
    return 0
}

instalar_dnsmasq_apt() {
    verificar_instalacion_existente || exit 1
    echo "Instalando dnsmasq con APT..."
    sudo apt update && sudo apt install -y dnsmasq
    echo ""
    echo "Seleccione el tipo de configuración a aplicar:"
    echo "1) Configuración básica (Puerto 5354, dominio 'juanpepe', interfaz ens33, DNS 8.8.8.8)"
    echo "2) Configuración personalizada"
    read -p "Opción (1/2): " opcion_config
    if [[ "$opcion_config" == "1" ]]; then
        puerto=5354
        dominio="juanpepe"
        interfaz="ens33"
        servidores_dns="8.8.8.8"
    elif [[ "$opcion_config" == "2" ]]; then
        read -p "Puerto (ej: 5354): " puerto
        [[ -z "$puerto" ]] && puerto=5354
        read -p "Dominio (ej: juanpepe): " dominio
        [[ -z "$dominio" ]] && dominio="juanpepe"
        read -p "Interfaz (ej: lo, eth0, ens33): " interfaz
        [[ -z "$interfaz" ]] && interfaz="ens33"
        read -p "Servidores DNS (ej: 8.8.8.8 1.1.1.1): " servidores_dns
        [[ -z "$servidores_dns" ]] && servidores_dns="8.8.8.8"
    else
        echo "Opción no válida. Se aplicará la configuración básica por defecto."
        puerto=5354
        dominio="juanpepe"
        interfaz="ens33"
        servidores_dns="8.8.8.8"
    fi
    if check_port "$puerto"; then
        nuevo_puerto=$(resolve_port_conflict "$puerto")
        puerto=$nuevo_puerto
    fi
    echo "Generando archivo de configuración en /etc/dnsmasq.conf..."
    sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
# Configuración de dnsmasq (APT)
port=$puerto
domain=$dominio
interface=$interfaz
no-resolv
EOF
    for dns in $servidores_dns; do
        echo "server=$dns" | sudo tee -a /etc/dnsmasq.conf > /dev/null
    done
    abrirPuertoUFW "$puerto"
    echo "dnsmasq instalado y configurado en el sistema (APT)."
    sudo systemctl restart dnsmasq
}

instalar_dnsmasq_docker() {
    verificar_instalacion_existente || exit 1
    instalar_docker
    echo "Instalando dnsmasq en Docker..."
    docker pull diego57709/dnsmasq:latest
    mkdir -p ~/dnsmasq-docker
    echo "Seleccione el tipo de configuración:"
    echo "1) Configuración básica (Puerto 5354, interfaz ens33, DNS 8.8.8.8)"
    echo "2) Configuración personalizada"
    read -p "Opción (1/2): " opcion_config
    CONFIG_FILE=~/dnsmasq-docker/dnsmasq.conf
    if [[ "$opcion_config" == "1" ]]; then
        puerto=5354
        interfaz="ens33"
        servidores_dns="8.8.8.8"
    elif [[ "$opcion_config" == "2" ]]; then
        read -p "Puerto (ej: 5354): " puerto
        [[ -z "$puerto" ]] && puerto=5354
        read -p "Interfaz (ej: eth0, ens33): " interfaz
        [[ -z "$interfaz" ]] && interfaz="ens33"
        read -p "Servidores DNS (ej: 8.8.8.8 1.1.1.1): " servidores_dns
        [[ -z "$servidores_dns" ]] && servidores_dns="8.8.8.8"
    else
        echo "Opción no válida. Se aplicará la configuración básica por defecto."
        puerto=5354
        interfaz="ens33"
        servidores_dns="8.8.8.8"
    fi
    if check_port "$puerto"; then
        nuevo_puerto=$(resolve_port_conflict "$puerto")
        puerto=$nuevo_puerto
    fi
    echo "Generando archivo de configuración en $CONFIG_FILE..."
    tee $CONFIG_FILE > /dev/null <<EOF
# Configuración de dnsmasq para Docker
port=$puerto
interface=$interfaz
no-resolv
EOF
    for dns in $servidores_dns; do
        echo "server=$dns"
    done >> "$CONFIG_FILE"
    abrirPuertoUFW "$puerto"
    docker run -d --name dnsmasq --network host \
        -p "$puerto:$puerto/udp" \
        -p "$puerto:$puerto/tcp" \
        -v ~/dnsmasq-docker/dnsmasq.conf:/etc/dnsmasq.conf \
        diego57709/dnsmasq:latest
    echo "dnsmasq instalado en Docker con configuración en el puerto $puerto."
}

instalar_dnsmasq_ansible() {
    verificar_instalacion_existente || exit 1
    instalar_ansible
    echo ""
    echo "Seleccione el tipo de configuración a aplicar con Ansible:"
    echo "1) Configuración básica (Puerto 5354, dominio 'juanpepe', interfaz ens33, DNS 8.8.8.8)"
    echo "2) Configuración personalizada"
    read -p "Opción (1/2): " opcion_config
    if [[ "$opcion_config" == "1" ]]; then
        puerto=5354
        dominio="juanpepe"
        interfaz="ens33"
        servidores_dns="8.8.8.8"
    elif [[ "$opcion_config" == "2" ]]; then
        read -p "Puerto (ej: 5354): " puerto
        [[ -z "$puerto" ]] && puerto=5354
        read -p "Dominio (ej: juanpepe): " dominio
        [[ -z "$dominio" ]] && dominio="juanpepe"
        read -p "Interfaz (ej: lo, eth0, ens33): " interfaz
        [[ -z "$interfaz" ]] && interfaz="ens33"
        read -p "Servidores DNS (ej: 8.8.8.8 1.1.1.1): " servidores_dns
        [[ -z "$servidores_dns" ]] && servidores_dns="8.8.8.8"
    else
        echo "Opción no válida. Se aplicará la configuración básica por defecto."
        puerto=5354
        dominio="juanpepe"
        interfaz="ens33"
        servidores_dns="8.8.8.8"
    fi
    if check_port "$puerto"; then
        nuevo_puerto=$(resolve_port_conflict "$puerto")
        puerto=$nuevo_puerto
    fi
    generar_inventario_ansible
    echo "Generando playbook de Ansible en /tmp/dnsmasq_install.yml..."
    cat <<EOF > /tmp/dnsmasq_install.yml
---
- name: Instalar y configurar dnsmasq con Ansible
  hosts: remote
  become: yes
  tasks:
    - name: Instalar dnsmasq
      apt:
        name: dnsmasq
        state: present
        update_cache: yes
    - name: Configurar /etc/dnsmasq.conf
      lineinfile:
        path: /etc/dnsmasq.conf
        regexp: "{{ item.regexp }}"
        line: "{{ item.line }}"
        create: yes
      with_items:
        - { regexp: '^port=',     line: 'port=$puerto' }
        - { regexp: '^domain=',   line: 'domain=$dominio' }
        - { regexp: '^interface=',line: 'interface=$interfaz' }
        - { regexp: '^no-resolv', line: 'no-resolv' }
    - name: Limpiar servidores DNS antiguos
      replace:
        path: /etc/dnsmasq.conf
        regexp: '^server=.*'
        replace: ''
      register: cleanup_result
    - name: Añadir nuevos servidores DNS
      lineinfile:
        path: /etc/dnsmasq.conf
        insertafter: EOF
        line: "server={{ item }}"
      with_items:
        - $servidores_dns
    - name: Abrir puerto en UFW (si UFW está activo)
      shell: |
        ufw allow $puerto/tcp
        ufw allow $puerto/udp
      ignore_errors: yes
    - name: Reiniciar dnsmasq
      service:
        name: dnsmasq
        state: restarted
    - name: Añadir comentario de Ansible
      lineinfile:
        path: /etc/dnsmasq.conf
        line: "# Ansible managed"
        insertbefore: BOF
      when: ansible_facts['pkg_mgr'] == 'apt'
EOF
    echo "Ejecutando playbook de Ansible en $ANSIBLE_REMOTE..."
    ansible-playbook -i "$INVENTORY_FILE" /tmp/dnsmasq_install.yml
    echo "dnsmasq instalado y configurado con Ansible en $ANSIBLE_REMOTE en el puerto $puerto."
}

#=====================================================
# 5. MENÚ PRINCIPAL Y LOGS
#=====================================================

mostrarMenu() {
    echo -e "\nMENÚ DE DNSMASQ"
    echo "---------------------------------"
    echo "1) $MENU_OPCION_1"
    echo "2) $MENU_OPCION_2"
    echo "3) $MENU_OPCION_3"
    echo "4) $MENU_OPCION_4"
    echo "0) Salir"
}

consultarLogs() {
    echo -e "\nCONSULTAR LOGS DE DNSMASQ"
    echo "---------------------------------"
    if [[ $SYSTEM_STATUS -eq 0 ]]; then
        log_source="system"
        echo "Se utilizará 'journalctl -u dnsmasq' para consultar los logs."
    elif [[ $DOCKER_STATUS -eq 0 || $DOCKER_STATUS -eq 2 ]]; then
        log_source="docker"
        container_id=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
        echo "Se utilizará 'docker logs' para consultar los logs del contenedor ($container_id)."
    elif [[ $ANSIBLE_STATUS -eq 0 ]]; then
        log_source="ansible"
        echo "Se utilizará 'journalctl -u dnsmasq' (Ansible usa systemd)."
    else
        echo "No se encontró dnsmasq en el sistema, Docker ni gestionado por Ansible para consultar logs."
        return
    fi
    echo ""
    echo "Seleccione la opción de filtrado:"
    echo "1) Mostrar TODOS los logs"
    echo "2) Mostrar logs DESDE una fecha (YYYY-MM-DD HH:MM:SS)"
    echo "3) Mostrar logs HASTA una fecha (YYYY-MM-DD HH:MM:SS)"
    echo "4) Mostrar logs en un RANGO de fechas"
    echo "5) Mostrar las últimas N líneas (ej: 10, 20, 30)"
    echo "6) Mostrar logs por PRIORIDAD (ej: err, warning, info, debug)"
    read -p "Opción: " filtro_opcion
    case "$filtro_opcion" in
        1)
            if [[ "$log_source" == "system" || "$log_source" == "ansible" ]]; then
                journalctl -u dnsmasq
            else
                docker logs "$container_id"
            fi
            ;;
        2)
            read -p "Ingrese la fecha de inicio (YYYY-MM-DD HH:MM:SS): " fecha_inicio
            if [[ "$log_source" == "system" || "$log_source" == "ansible" ]]; then
                journalctl -u dnsmasq --since "$fecha_inicio"
            else
                docker logs "$container_id" --since "$fecha_inicio"
            fi
            ;;
        3)
            read -p "Ingrese la fecha final (YYYY-MM-DD HH:MM:SS): " fecha_fin
            if [[ "$log_source" == "system" || "$log_source" == "ansible" ]]; then
                journalctl -u dnsmasq --until "$fecha_fin"
            else
                docker logs "$container_id" --until "$fecha_fin"
            fi
            ;;
        4)
            read -p "Ingrese la fecha de inicio (YYYY-MM-DD HH:MM:SS): " fecha_inicio
            read -p "Ingrese la fecha final (YYYY-MM-DD HH:MM:SS): " fecha_fin
            if [[ "$log_source" == "system" || "$log_source" == "ansible" ]]; then
                journalctl -u dnsmasq --since "$fecha_inicio" --until "$fecha_fin"
            else
                docker logs "$container_id" --since "$fecha_inicio" --until "$fecha_fin"
            fi
            ;;
        5)
            read -p "Ingrese la cantidad de líneas a mostrar: " num_lineas
            if [[ "$log_source" == "system" || "$log_source" == "ansible" ]]; then
                journalctl -u dnsmasq -n "$num_lineas"
            else
                docker logs "$container_id" --tail "$num_lineas"
            fi
            ;;
        6)
            read -p "Ingrese la prioridad a filtrar (ej: err, warning, info, debug): " prioridad
            if [[ "$log_source" == "system" || "$log_source" == "ansible" ]]; then
                journalctl -u dnsmasq -p "$prioridad"
            else
                docker logs "$container_id" | grep -i "$prioridad"
            fi
            ;;
        *)
            echo "Opción no válida."
            ;;
    esac
}

#=====================================================
# 6. GESTIÓN Y CONFIGURACIÓN DE DNSMASQ EN EL SISTEMA
#=====================================================

gestionarServicioSistema() {
    echo -e "\nGESTIÓN DE DNSMASQ EN EL SISTEMA"
    echo "---------------------------------"
    echo "1) Iniciar servicio"
    echo "2) Detener servicio"
    echo "3) Reiniciar servicio"
    echo "4) Estado del servicio"
    read -p "Seleccione una opción: " opcion
    case "$opcion" in
        1) sudo systemctl start dnsmasq && echo "Servicio iniciado." ;;
        2) sudo systemctl stop dnsmasq && echo "Servicio detenido." ;;
        3) sudo systemctl restart dnsmasq && echo "Servicio reiniciado." ;;
        4) systemctl status dnsmasq ;;
        *) echo "Opción no válida." ;;
    esac
}

cambiarPuertoSistema() {
    viejo_puerto=$(grep "^port=" /etc/dnsmasq.conf | cut -d'=' -f2)
    read -p "Ingrese el nuevo puerto: " nuevo_puerto
    if check_port "$nuevo_puerto"; then
        nuevo_puerto=$(resolve_port_conflict "$nuevo_puerto")
    fi
    if [[ "$viejo_puerto" != "$nuevo_puerto" ]]; then
        cerrarPuertoUFW "$viejo_puerto"
        abrirPuertoUFW "$nuevo_puerto"
    fi
    sudo sed -i "s/^port=.*/port=$nuevo_puerto/" /etc/dnsmasq.conf
    sudo systemctl restart dnsmasq
    echo "Puerto cambiado a $nuevo_puerto y servicio reiniciado."
}

cambiarDominioSistema() {
    read -p "Ingrese el nuevo dominio: " nuevo_dominio
    [[ -z "$nuevo_dominio" ]] && nuevo_dominio="local"
    sudo sed -i "s/^domain=.*/domain=$nuevo_dominio/" /etc/dnsmasq.conf
    sudo systemctl restart dnsmasq
    echo "Dominio cambiado a $nuevo_dominio y servicio reiniciado."
}

cambiarInterfazSistema() {
    read -p "Ingrese la nueva interfaz (ej: eth0, ens33): " nueva_interfaz
    [[ -z "$nueva_interfaz" ]] && nueva_interfaz="ens33"
    sudo sed -i "s/^interface=.*/interface=$nueva_interfaz/" /etc/dnsmasq.conf
    sudo systemctl restart dnsmasq
    echo "Interfaz cambiada a $nueva_interfaz y servicio reiniciado."
}

cambiarServidoresDNSSistema() {
    read -p "Ingrese los nuevos servidores DNS (separados por espacios): " nuevos_dns
    sudo sed -i '/^server=/d' /etc/dnsmasq.conf
    for dns in $nuevos_dns; do
        echo "server=$dns" | sudo tee -a /etc/dnsmasq.conf > /dev/null
    done
    sudo systemctl restart dnsmasq
    echo "Servidores DNS actualizados a: $nuevos_dns y servicio reiniciado."
}

añadirHostsSistema() {
    read -p "Ingrese el nombre del host (ej: servidor.local): " nombre_host
    read -p "Ingrese la IP correspondiente: " ip_host
    echo "host-record=$nombre_host,$ip_host" | sudo tee -a /etc/dnsmasq.conf > /dev/null
    sudo systemctl restart dnsmasq
    echo "Se ha añadido el host $nombre_host con IP $ip_host y el servicio ha sido reiniciado."
}

configurarServicioSistema() {
    echo "Seleccione la opción a configurar:"
    echo "---------------------------------"
    echo "1) Cambiar puerto"
    echo "2) Cambiar dominio"
    echo "3) Cambiar interfaz"
    echo "4) Cambiar servidores DNS"
    echo "5) Añadir host"
    read -p "Opción: " opcion
    case "$opcion" in
        1) cambiarPuertoSistema ;;
        2) cambiarDominioSistema ;;
        3) cambiarInterfazSistema ;;
        4) cambiarServidoresDNSSistema ;;
        5) añadirHostsSistema ;;
        *) echo "Opción no válida." ;;
    esac
}

eliminarDnsmasqSistema() {
    if [[ -f /etc/dnsmasq.conf ]]; then
        current_port=$(grep "^port=" /etc/dnsmasq.conf | cut -d'=' -f2)
        cerrarPuertoUFW "$current_port"
    fi
    echo "Eliminando dnsmasq del sistema..."
    sudo systemctl stop dnsmasq
    sudo apt remove -y dnsmasq
    sudo apt autoremove -y
    echo "dnsmasq ha sido eliminado del sistema."
    exit 1
}

#=====================================================
# 7. GESTIÓN Y CONFIGURACIÓN DE DNSMASQ EN DOCKER
#=====================================================

gestionarServicioDocker() {
    echo -e "\nGESTIÓN DE DNSMASQ EN DOCKER"
    echo "---------------------------------"
    echo "1) Iniciar contenedor"
    echo "2) Detener contenedor"
    echo "3) Reiniciar contenedor"
    echo "4) Estado del contenedor"
    read -p "Seleccione una opción: " opcion
    CONTAINER_ID=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
    case "$opcion" in
        1) docker start "$CONTAINER_ID" && echo "Contenedor iniciado." ;;
        2) docker stop "$CONTAINER_ID" && echo "Contenedor detenido." ;;
        3) docker restart "$CONTAINER_ID" && echo "Contenedor reiniciado." ;;
        4) docker ps --filter "id=$CONTAINER_ID" --format "ID: {{.ID}}, Estado: {{.Status}}" ;;
        *) echo "Opción no válida." ;;
    esac
}

cambiarPuertoDocker() {
    CONFIG_FILE=~/dnsmasq-docker/dnsmasq.conf
    viejo_puerto=$(grep "^port=" "$CONFIG_FILE" | cut -d'=' -f2)
    read -p "Ingrese el nuevo puerto: " nuevo_puerto
    if check_port "$nuevo_puerto"; then
        nuevo_puerto=$(resolve_port_conflict "$nuevo_puerto")
    fi
    if [[ "$viejo_puerto" != "$nuevo_puerto" ]]; then
        cerrarPuertoUFW "$viejo_puerto"
        abrirPuertoUFW "$nuevo_puerto"
    fi
    sed -i "s/^port=.*/port=$nuevo_puerto/" "$CONFIG_FILE"
    docker stop dnsmasq && docker rm dnsmasq
    docker run -d --name dnsmasq --network host \
        -p "$nuevo_puerto:$nuevo_puerto/udp" -p "$nuevo_puerto:$nuevo_puerto/tcp" \
        -v ~/dnsmasq-docker/dnsmasq.conf:/etc/dnsmasq.conf \
        diego57709/dnsmasq:latest
    echo "Puerto cambiado a $nuevo_puerto y contenedor reiniciado."
}

cambiarDominioDocker() {
    CONFIG_FILE=~/dnsmasq-docker/dnsmasq.conf
    read -p "Ingrese el nuevo dominio: " nuevo_dominio
    [[ -z "$nuevo_dominio" ]] && nuevo_dominio="local"
    sed -i "s/^domain=.*/domain=$nuevo_dominio/" "$CONFIG_FILE"
    docker stop dnsmasq 2>/dev/null
    docker rm dnsmasq 2>/dev/null
    current_port=$(grep "^port=" "$CONFIG_FILE" | cut -d'=' -f2)
    docker run -d --name dnsmasq --network host \
        -p "$current_port:$current_port/udp" -p "$current_port:$current_port/tcp" \
        -v ~/dnsmasq-docker/dnsmasq.conf:/etc/dnsmasq.conf \
        diego57709/dnsmasq:latest
    echo "Dominio cambiado a $nuevo_dominio y contenedor reiniciado."
}

cambiarInterfazDocker() {
    CONFIG_FILE=~/dnsmasq-docker/dnsmasq.conf
    read -p "Ingrese la nueva interfaz (ej: eth0, ens33): " nueva_interfaz
    [[ -z "$nueva_interfaz" ]] && nueva_interfaz="ens33"
    sed -i "s/^interface=.*/interface=$nueva_interfaz/" "$CONFIG_FILE"
    docker stop dnsmasq 2>/dev/null
    docker rm dnsmasq 2>/dev/null
    current_port=$(grep "^port=" "$CONFIG_FILE" | cut -d'=' -f2)
    docker run -d --name dnsmasq --network host \
        -p "$current_port:$current_port/udp" -p "$current_port:$current_port/tcp" \
        -v ~/dnsmasq-docker/dnsmasq.conf:/etc/dnsmasq.conf \
        diego57709/dnsmasq:latest
    echo "Interfaz cambiada a $nueva_interfaz y contenedor reiniciado."
}

cambiarServidoresDNSDocker() {
    CONFIG_FILE=~/dnsmasq-docker/dnsmasq.conf
    read -p "Ingrese los nuevos servidores DNS (separados por espacios): " nuevos_dns
    sed -i '/^server=/d' "$CONFIG_FILE"
    for dns in $nuevos_dns; do
        echo "server=$dns" >> "$CONFIG_FILE"
    done
    docker stop dnsmasq 2>/dev/null
    docker rm dnsmasq 2>/dev/null
    current_port=$(grep "^port=" "$CONFIG_FILE" | cut -d'=' -f2)
    docker run -d --name dnsmasq --network host \
        -p "$current_port:$current_port/udp" -p "$current_port:$current_port/tcp" \
        -v ~/dnsmasq-docker/dnsmasq.conf:/etc/dnsmasq.conf \
        diego57709/dnsmasq:latest
    echo "Servidores DNS actualizados a: $nuevos_dns y contenedor reiniciado."
}

añadirHostsDocker() {
    CONFIG_FILE=~/dnsmasq-docker/dnsmasq.conf
    read -p "Ingrese el nombre del host (ej: servidor.local): " nombre_host
    read -p "Ingrese la IP correspondiente: " ip_host
    echo "host-record=$nombre_host,$ip_host" >> "$CONFIG_FILE"
    docker stop dnsmasq 2>/dev/null
    docker rm dnsmasq 2>/dev/null
    current_port=$(grep "^port=" "$CONFIG_FILE" | cut -d'=' -f2)
    docker run -d --name dnsmasq --network host \
        -p "$current_port:$current_port/udp" -p "$current_port:$current_port/tcp" \
        -v ~/dnsmasq-docker/dnsmasq.conf:/etc/dnsmasq.conf \
        diego57709/dnsmasq:latest
    echo "Se ha añadido el host $nombre_host con IP $ip_host y el contenedor ha sido reiniciado."
}

configurarServicioDocker() {
    echo "Seleccione la opción a configurar:"
    echo "---------------------------------"
    echo "1) Cambiar puerto"
    echo "2) Cambiar dominio"
    echo "3) Cambiar interfaz"
    echo "4) Cambiar servidores DNS"
    echo "5) Añadir host"
    read -p "Opción: " opcion
    case "$opcion" in
        1) cambiarPuertoDocker ;;
        2) cambiarDominioDocker ;;
        3) cambiarInterfazDocker ;;
        4) cambiarServidoresDNSDocker ;;
        5) añadirHostsDocker ;;
        *) echo "Opción no válida." ;;
    esac
}

eliminarDnsmasqDocker() {
    CONFIG_FILE=~/dnsmasq-docker/dnsmasq.conf
    CONTAINER_ID=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
    echo -e "\nELIMINAR DNSMASQ EN DOCKER"
    echo "---------------------------------"
    echo "1) Borrar solo el contenedor"
    echo "2) Borrar contenedor e imagen"
    echo "0) Volver al menú"
    read -p "Seleccione una opción: " opcion
    case "$opcion" in
        1)
            docker stop "$CONTAINER_ID" && docker rm "$CONTAINER_ID"
            echo "Contenedor eliminado correctamente."
            ;;
        2)
            docker stop "$CONTAINER_ID" && docker rm "$CONTAINER_ID"
            docker rmi diego57709/dnsmasq:latest
            if [[ -f "$CONFIG_FILE" ]]; then
                current_port=$(grep "^port=" "$CONFIG_FILE" | cut -d'=' -f2)
                cerrarPuertoUFW "$current_port"
            fi
            echo "Contenedor e imagen eliminados correctamente."
            exit 1
            ;;
        0)
            return
            ;;
        *)
            echo "Opción no válida."
            ;;
    esac
}

#=====================================================
# 8. GESTIÓN Y CONFIGURACIÓN DE DNSMASQ EN ANSIBLE
#=====================================================

gestionarServicioAnsible() {
    echo -e "\nGESTIÓN DE DNSMASQ (ANSIBLE)"
    echo "---------------------------------"
    echo "1) Iniciar servicio"
    echo "2) Detener servicio"
    echo "3) Reiniciar servicio"
    echo "4) Estado del servicio"
    read -p "Seleccione una opción: " opcion
    case "$opcion" in
        1) ansible_dnsmasq_service "started" ;;
        2) ansible_dnsmasq_service "stopped" ;;
        3) ansible_dnsmasq_service "restarted" ;;
        4) ansible_dnsmasq_status ;;
        *) echo "Opción no válida." ;;
    esac
}

ansible_dnsmasq_service() {
    local estado_ansible=$1
    generar_inventario_ansible
    echo "Creando playbook para '$estado_ansible' dnsmasq en Ansible..."
    cat <<EOF > /tmp/dnsmasq_service.yml
---
- name: Gestionar servicio dnsmasq con Ansible
  hosts: remote
  become: yes
  tasks:
    - name: Asegurar dnsmasq en estado '$estado_ansible'
      service:
        name: dnsmasq
        state: $estado_ansible
EOF
    echo "Ejecutando playbook de Ansible para '$estado_ansible' dnsmasq en $ANSIBLE_REMOTE..."
    ansible-playbook -i "$INVENTORY_FILE" /tmp/dnsmasq_service.yml
    echo "Operación '$estado_ansible' finalizada."
}

ansible_dnsmasq_status() {
    generar_inventario_ansible
    echo "Creando playbook para consultar 'status' de dnsmasq..."
    cat <<'EOF' > /tmp/dnsmasq_status.yml
---
- name: Consultar estado de dnsmasq con Ansible
  hosts: remote
  become: yes
  tasks:
    - name: Ver estado del servicio con systemd
      shell: systemctl status dnsmasq
      register: dnsmasq_status
    - name: Mostrar salida
      debug:
        var: dnsmasq_status.stdout
EOF
    echo "Ejecutando playbook de Ansible para consultar el estado en $ANSIBLE_REMOTE..."
    ansible-playbook -i "$INVENTORY_FILE" /tmp/dnsmasq_status.yml
}

ansible_cambiarPuerto() {
    read -p "Ingrese el nuevo puerto: " nuevo_puerto
    generar_inventario_ansible
    cat <<EOF > /tmp/dnsmasq_conf_port.yml
---
- name: Cambiar puerto dnsmasq vía Ansible
  hosts: remote
  become: yes
  tasks:
    - name: Reemplazar línea port= en /etc/dnsmasq.conf
      lineinfile:
        path: /etc/dnsmasq.conf
        regexp: '^port='
        line: "port=$nuevo_puerto"
    - name: Reiniciar dnsmasq
      service:
        name: dnsmasq
        state: restarted
EOF
    ansible-playbook -i "$INVENTORY_FILE" /tmp/dnsmasq_conf_port.yml
    echo "Se cambió el puerto a $nuevo_puerto."
}

ansible_cambiarDominio() {
    read -p "Ingrese el nuevo dominio: " nuevo_dominio
    [[ -z "$nuevo_dominio" ]] && nuevo_dominio="local"
    generar_inventario_ansible
    cat <<EOF > /tmp/dnsmasq_conf_domain.yml
---
- name: Cambiar dominio en /etc/dnsmasq.conf con Ansible
  hosts: remote
  become: yes
  tasks:
    - name: Reemplazar línea domain=
      lineinfile:
        path: /etc/dnsmasq.conf
        regexp: '^domain='
        line: "domain=$nuevo_dominio"
    - name: Reiniciar dnsmasq
      service:
        name: dnsmasq
        state: restarted
EOF
    ansible-playbook -i "$INVENTORY_FILE" /tmp/dnsmasq_conf_domain.yml
    echo "Se cambió el dominio a $nuevo_dominio."
}

ansible_cambiarInterfaz() {
    read -p "Ingrese la nueva interfaz (ej: eth0, ens33): " nueva_interfaz
    [[ -z "$nueva_interfaz" ]] && nueva_interfaz="ens33"
    generar_inventario_ansible
    cat <<EOF > /tmp/dnsmasq_conf_iface.yml
---
- name: Cambiar interfaz en /etc/dnsmasq.conf con Ansible
  hosts: remote
  become: yes
  tasks:
    - name: Reemplazar línea interface=
      lineinfile:
        path: /etc/dnsmasq.conf
        regexp: '^interface='
        line: "interface=$nueva_interfaz"
    - name: Reiniciar dnsmasq
      service:
        name: dnsmasq
        state: restarted
EOF
    ansible-playbook -i "$INVENTORY_FILE" /tmp/dnsmasq_conf_iface.yml
    echo "Se cambió la interfaz a $nueva_interfaz."
}

ansible_cambiarServidoresDNS() {
    read -p "Ingrese los nuevos servidores DNS (separados por espacios): " nuevos_dns
    generar_inventario_ansible
    cat <<EOF > /tmp/dnsmasq_conf_dns.yml
---
- name: Cambiar servidores DNS en /etc/dnsmasq.conf con Ansible
  hosts: remote
  become: yes
  tasks:
    - name: Eliminar líneas server= anteriores
      replace:
        path: /etc/dnsmasq.conf
        regexp: '^server=.*'
        replace: ''
    - name: Añadir nuevos servidores DNS
      lineinfile:
        path: /etc/dnsmasq.conf
        insertafter: EOF
        line: "server={{ item }}"
      with_items:
EOF
    for dns in $nuevos_dns; do
        echo "        - $dns" >> /tmp/dnsmasq_conf_dns.yml
    done
    cat <<'EOF' >> /tmp/dnsmasq_conf_dns.yml
    - name: Reiniciar dnsmasq
      service:
        name: dnsmasq
        state: restarted
EOF
    ansible-playbook -i "$INVENTORY_FILE" /tmp/dnsmasq_conf_dns.yml
    echo "Servidores DNS actualizados a: $nuevos_dns."
}

ansible_añadirHosts() {
    read -p "Ingrese el nombre del host (ej: servidor.local): " nombre_host
    read -p "Ingrese la IP correspondiente: " ip_host
    generar_inventario_ansible
    cat <<EOF > /tmp/dnsmasq_conf_hosts.yml
---
- name: Añadir host en /etc/dnsmasq.conf con Ansible
  hosts: remote
  become: yes
  tasks:
    - name: Añadir línea host-record
      lineinfile:
        path: /etc/dnsmasq.conf
        insertafter: EOF
        line: "host-record=$nombre_host,$ip_host"
    - name: Reiniciar dnsmasq
      service:
        name: dnsmasq
        state: restarted
EOF
    ansible-playbook -i "$INVENTORY_FILE" /tmp/dnsmasq_conf_hosts.yml
    echo "Se ha añadido el host $nombre_host con IP $ip_host."
}

eliminarDnsmasqAnsible() {
    generar_inventario_ansible
    echo "Eliminando dnsmasq con Ansible en $ANSIBLE_REMOTE..."
    cat <<EOF > /tmp/dnsmasq_remove.yml
---
- name: Eliminar dnsmasq con Ansible
  hosts: remote
  become: yes
  tasks:
    - name: Detener el servicio dnsmasq si está activo
      service:
        name: dnsmasq
        state: stopped
      ignore_errors: yes
    - name: Desinstalar paquete dnsmasq
      apt:
        name: dnsmasq
        state: absent
        purge: yes
        update_cache: yes
      ignore_errors: yes
    - name: Eliminar /etc/dnsmasq.conf si existe
      file:
        path: /etc/dnsmasq.conf
        state: absent
      ignore_errors: yes
EOF
    ansible-playbook -i "$INVENTORY_FILE" /tmp/dnsmasq_remove.yml
    echo "dnsmasq ha sido eliminado vía Ansible en $ANSIBLE_REMOTE."
    exit 1
}

#=====================================================
# 9. INICIO DEL SCRIPT
#=====================================================

check_dnsmasq_system
SYSTEM_STATUS=$?
check_dnsmasq_docker
DOCKER_STATUS=$?
check_dnsmasq_ansible
ANSIBLE_STATUS=$?
IP_ADDRESS=$(get_ip_address)

#!/bin/bash

help() {
    echo "Uso: $0 [opciones]"
    echo ""
    echo "Opciones disponibles:"
    echo "  --help                                                      Mostrar ayuda"
    echo "  --install <apt|docker|ansible>                              Instalar dnsmasq"
    echo "  --gestion <apt|docker|ansible> <start|stop|restart|status>  Gestionar dnsmasq"
    echo "  --uninstall <apt|docker|ansible>                            Eliminar dnsmasq"
}

if [[ $# -ge 1 ]]; then
    case "$1" in
        --help)
            help
            exit 0
            ;;
        --install)
            [[ -z "$2" ]] && { echo "Error: Falta el método de instalación."; help; exit 1; }
            case "$2" in
                apt) instalar_dnsmasq_apt ;;
                docker) instalar_dnsmasq_docker ;;
                ansible) instalar_dnsmasq_ansible ;;
                *) echo "Error: Método inválido. Usa: $0 --install <apt|docker|ansible>"; exit 1 ;;
            esac
            exit 0
            ;;
        --configuracion)
            [[ -z "$2" ]] && { echo "Error: Falta el método de instalación."; help; exit 1; }
            case "$2" in
                apt) configurarServicioSistema ;;
                docker) configurarServicioDocker ;;
                ansible) configurarServicioAnsible ;;
                *) echo "Error: Método inválido. Usa: $0 --configuracion <apt|docker|ansible>"; exit 1 ;;
            esac
            exit 0
            ;;
        --gestion)
            [[ -z "$2" ]] && { echo "Error: Falta la acción a realizar."; help; exit 1; }
            case "$2" in
                apt)
                    case "$3" in
                        start) sudo systemctl start dnsmasq ;;
                        stop) sudo systemctl stop dnsmasq ;;
                        restart) sudo systemctl restart dnsmasq ;;
                        status) systemctl status dnsmasq ;;
                        *) echo "Error: Acción inválida. Usa: $0 --gestion apt <start|stop|restart|status>"; exit 1 ;;
                    esac
                    ;;
                docker)
                    CONTAINER_ID=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
                    case "$3" in
                        start) docker start "$CONTAINER_ID" && echo "Contenedor iniciado." ;;
                        stop) docker stop "$CONTAINER_ID" && echo "Contenedor detenido." ;;
                        restart) docker restart "$CONTAINER_ID" && echo "Contenedor reiniciado." ;;
                        status) docker ps --filter "id=$CONTAINER_ID" --format "ID: {{.ID}}, Estado: {{.Status}}" ;;
                        *) echo "Error: Acción inválida. Usa: $0 --gestion docker <start|stop|restart|status>"; exit 1 ;;
                    esac
                    ;;
                ansible)
                    case "$3" in
                        start) ansible_dnsmasq_service "started" ;;
                        stop) ansible_dnsmasq_service "stopped" ;;
                        restart) ansible_dnsmasq_service "restarted" ;;
                        status) ansible_dnsmasq_status ;;
                        *) echo "Error: Acción inválida. Usa: $0 --gestion ansible <start|stop|restart|status>"; exit 1 ;;
                    esac
                    ;;
                *) echo "Error: Acción inválida. Usa: $0 --gestion <apt|docker|ansible> <start|stop|restart|status>"; exit 1 ;;
            esac
            exit 0
            ;;
        --logs)
            [[ -z "$2" ]] && { echo "Error: Falta el método de instalación (apt, docker o ansible)."; help; exit 1; }
            case "$2" in
                apt)
                    echo "Consultando logs con (APT)..."
                    journalctl -u dnsmasq
                    ;;
                docker)
                    CONTAINER_ID=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
                    if [[ -z "$CONTAINER_ID" ]]; then
                        echo "Error: No hay un contenedor dnsmasq en Docker."
                        exit 1
                    fi
                    echo "Consultando logs del contenedor dnsmasq en Docker..."
                    docker logs "$CONTAINER_ID"
                    ;;
                ansible)
                    echo "Consultando logs con Ansible..."
                    journalctl -u dnsmasq
                    ;;
                *)
                    echo "Error: Método inválido. Usa: $0 --logs <apt|docker|ansible>"
                    exit 1
                    ;;
            esac
            exit 0
            ;;
        --uninstall)
            [[ -z "$2" ]] && { echo "Error: Falta el método de instalación."; help; exit 1; }
            case "$2" in
                apt) eliminarDnsmasqSistema ;;
                docker) eliminarDnsmasqDocker ;;
                ansible) eliminarDnsmasqAnsible ;;
                *) echo "Error: Método inválido. Usa: $0 --uninstall <apt|docker|ansible>"; exit 1 ;;
            esac
            exit 0
            ;;
        *)
            echo "Error: Opción no reconocida."
            help
            exit 1
            ;;
    esac
fi

if [[ $SYSTEM_STATUS -eq 1 && $DOCKER_STATUS -eq 1 && $ANSIBLE_STATUS -eq 1 ]]; then
    estadoSistema
    echo "Seleccione el método de instalación:"
    echo "---------------------------------"
    echo "1) APT (paquete del sistema)"
    echo "2) Docker (contenedor)"
    echo "3) Ansible"
    echo "0) Salir"
    read -p "Seleccione una opción (1/2/3/0): " metodo
    case "$metodo" in
        1)
            instalar_dnsmasq_apt
            SYSTEM_STATUS=0
            ;;
        2)
            instalar_dnsmasq_docker
            DOCKER_STATUS=0
            ;;
        3)
            instalar_dnsmasq_ansible
            ANSIBLE_STATUS=0
            ;;
        0)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo "Opción no válida. Saliendo..."
            exit 1
            ;;
    esac
fi

if [[ $SYSTEM_STATUS -eq 0 ]]; then
    MENU_OPCION_1="Gestionar dnsmasq (Sistema)"
    MENU_OPCION_2="Consultar logs"
    MENU_OPCION_3="Configurar el servicio"
    MENU_OPCION_4="Eliminar dnsmasq del sistema"
    MENU_FUNCION_1="gestionarServicioSistema"
    MENU_FUNCION_2="consultarLogs"
    MENU_FUNCION_3="configurarServicioSistema"
    MENU_FUNCION_4="eliminarDnsmasqSistema"
fi

if [[ $DOCKER_STATUS -ne 1 ]]; then
    MENU_OPCION_1="Gestionar dnsmasq (Docker)"
    MENU_OPCION_2="Consultar logs"
    MENU_OPCION_3="Configurar el servicio"
    MENU_OPCION_4="Eliminar dnsmasq de Docker"
    MENU_FUNCION_1="gestionarServicioDocker"
    MENU_FUNCION_2="consultarLogs"
    MENU_FUNCION_3="configurarServicioDocker"
    MENU_FUNCION_4="eliminarDnsmasqDocker"
fi

if [[ $ANSIBLE_STATUS -ne 1 ]]; then
    MENU_OPCION_1="Gestionar dnsmasq (Ansible)"
    MENU_OPCION_2="Consultar logs"
    MENU_OPCION_3="Configurar el servicio"
    MENU_OPCION_4="Eliminar dnsmasq de Ansible"
    MENU_FUNCION_1="gestionarServicioAnsible"
    MENU_FUNCION_2="consultarLogs"
    MENU_FUNCION_3="configurarServicioAnsible"
    MENU_FUNCION_4="eliminarDnsmasqAnsible"
fi

while true; do
    estadoSistema
    mostrarMenu
    read -p "Seleccione una opción: " opcionMenu
    case "$opcionMenu" in
        1) [[ -n "$MENU_FUNCION_1" ]] && $MENU_FUNCION_1 ;;
        2) $MENU_FUNCION_2 ;;
        3) $MENU_FUNCION_3 ;;
        4) [[ -n "$MENU_FUNCION_4" ]] && $MENU_FUNCION_4 ;;
        0) echo "Saliendo..." && exit 0 ;;
        *) echo "Opción no válida." ;;
    esac
done
