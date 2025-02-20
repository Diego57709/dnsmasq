#!/bin/bash

#=====================================================
# 1. FUNCIONES GENERALES
#=====================================================

#-----------------------------------------------------
# Funciones generales
#-----------------------------------------------------

# Función para obtener la IP del equipo
get_ip_address() {
    ip -o -4 addr show | tr -s ' ' | grep -Ev ' lo | docker' | awk '{print $2 ":", $4}' | cut -d/ -f1
}



# Función para ver si esta en el sistema
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
        return 0  # En uso
    else
        return 1  # Libre
    fi
}

# Función para resolver conflicto de puerto
resolve_port_conflict() {
    local current_port=$1
    local new_port

    while true; do
        read -p "El puerto $current_port está en uso. Ingrese un nuevo puerto: " new_port

        if [[ ! "$new_port" =~ ^[0-9]+$ ]]; then
            echo "❌ Error: Debe ingresar un número de puerto válido."
            continue
        fi

        if ! check_port "$new_port"; then
            echo "$new_port"
            return
        else
            echo "❌ El puerto $new_port también está en uso. Intente con otro."
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
        sudo apt install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

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
        echo "El usuario $USER ha sido añadido al grupo docker."
        echo "🔴 Es recomendable reiniciar el sistema para aplicar los cambios."
    fi
}

instalar_ansible() {
    echo "Verificando si Ansible está instalado..."
    if ! command -v ansible &> /dev/null; then
        echo "Ansible no está instalado. Instalándolo..."
        sudo apt update
        sudo apt install -y ansible
    else
        echo "Ansible ya está instalado."
    fi
}

#=====================================================
# 2. GESTIÓN DE PUERTOS Y UFW
#=====================================================

#-----------------------------------------------------
# Funciones para abrir y cerrar puertos con ufw
#-----------------------------------------------------

habilitarUFW() {
    if command -v ufw &> /dev/null; then
        activoUFW=$(sudo ufw status | grep -i "Status: active")
        if [[ -z "$activoUFW" ]]; then
            echo "UFW está deshabilitado. Activándolo..."
            sudo ufw --force enable
            echo "UFW ha sido activado."
        fi
    fi
}

abrirPuertoUFW() {
    local port=$1
    if command -v ufw &> /dev/null; then
        habilitarUFW
        sudo ufw allow "$port"/tcp >/dev/null
        sudo ufw allow "$port"/udp >/dev/null
        echo "Puerto $port abierto en UFW."
    fi
}

cerrarPuertoUFW() {
    local port=$1
    if command -v ufw &> /dev/null; then
        sudo ufw delete allow "$port"/tcp >/dev/null 2>&1
        sudo ufw delete allow "$port"/udp >/dev/null 2>&1
        echo "Puerto $port cerrado en UFW."
    fi
}

#=====================================================
# 3. ESTADO DEL SISTEMA
#=====================================================

#-----------------------------------------------------
# Función para mostrar el estado actual del sistema
#-----------------------------------------------------

estadoSistema() {
    echo "-----------------------------------------------------"
    echo " Estado actual del sistema"
    echo "-----------------------------------------------------"
    echo -e "IP del equipo: \n$(get_ip_address)"

    if [[ $SYSTEM_STATUS -eq 0 ]]; then
        echo "dnsmasq está instalado por APT."

        # Obtener interfaz e IP desde la configuración de dnsmasq
        if [[ -f /etc/dnsmasq.conf ]]; then
            interfaz=$(grep "^interface=" /etc/dnsmasq.conf | cut -d'=' -f2)
            puerto=$(grep "^port=" /etc/dnsmasq.conf | cut -d'=' -f2)
            [[ -z "$puerto" ]]
            ip=$(ip -o -4 addr show "$interfaz" | awk '{print $4}' | cut -d/ -f1)
            echo "Interfaz: $interfaz | IP: $ip | Puerto: $puerto"
        fi
    elif [[ $DOCKER_STATUS -eq 0 ]]; then
        echo "dnsmasq está corriendo en un contenedor Docker."

        # Obtener interfaz e IP desde el archivo de configuración de Docker
        CONFIG_FILE=~/dnsmasq-docker/dnsmasq.conf
        if [[ -f "$CONFIG_FILE" ]]; then
            interfaz=$(grep "^interface=" "$CONFIG_FILE" | cut -d'=' -f2)
            puerto=$(grep "^port=" "$CONFIG_FILE" | cut -d'=' -f2)
            [[ -z "$puerto" ]]
            ip=$(ip -o -4 addr show "$interfaz" | awk '{print $4}' | cut -d/ -f1)
            echo "Interfaz (Docker): $interfaz | IP: $ip | Puerto: $puerto"
        fi
    elif [[ $DOCKER_STATUS -eq 2 ]]; then
        echo "dnsmasq está en Docker pero el contenedor está detenido."
    elif [[ $DOCKER_STATUS -eq 3 ]]; then
        echo "dnsmasq está en Docker como imagen, pero no hay contenedor creado."
    elif [[ $ANSIBLE_STATUS -eq 0 ]]; then
        echo "dnsmasq fue instalado con Ansible."

        # Obtener interfaz e IP si fue configurado con Ansible
        if [[ -f /etc/dnsmasq.conf ]]; then
            interfaz=$(grep "^interface=" /etc/dnsmasq.conf | cut -d'=' -f2)
            puerto=$(grep "^port=" /etc/dnsmasq.conf | cut -d'=' -f2)
            [[ -z "$puerto" ]]
            ip=$(ip -o -4 addr show "$interfaz" | awk '{print $4}' | cut -d/ -f1)
            echo "Interfaz (Ansible): $interfaz | IP: $ip | Puerto: $puerto"
        fi
    else
        echo "dnsmasq NO está instalado en el sistema, Docker ni gestionado por Ansible."
    fi
}


#=====================================================
# 4. INSTALACIÓN DE DNSMASQ
#=====================================================

#-----------------------------------------------------
# Funciones para la instalación
#-----------------------------------------------------

# Función para instalar dnsmasq mediante APT
instalar_dnsmasq_apt() {
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

    # Verificar si el puerto está en uso
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

    # Verificar si el puerto está en uso
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

    docker run -d --name dnsmasq -p $puerto:$puerto/udp -p $puerto:$puerto/tcp \
        -v ~/dnsmasq-docker/dnsmasq.conf:/etc/dnsmasq.conf \
        diego57709/dnsmasq:latest 

    echo "dnsmasq instalado en Docker con configuración en el puerto $puerto."
}



instalar_dnsmasq_ansible() {
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

    INVENTORY_FILE="/etc/ansible/hosts"
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        echo "Creando inventario de Ansible en $INVENTORY_FILE..."
        sudo tee "$INVENTORY_FILE" > /dev/null <<EOF
[local]
localhost ansible_connection=local
EOF
    fi

    echo "Generando playbook de Ansible en /tmp/dnsmasq_install.yml..."
    cat <<EOF > /tmp/dnsmasq_install.yml
---
- name: Instalar y configurar dnsmasq con Ansible
  hosts: localhost
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

    echo "Ejecutando playbook de Ansible..."
    ansible-playbook -i "$INVENTORY_FILE" /tmp/dnsmasq_install.yml

    echo "dnsmasq instalado y configurado con Ansible en el puerto $puerto."
}

#=====================================================
# 5. MENÚ PRINCIPAL Y LOGS
#=====================================================

#-----------------------------------------------------
# Funciones para el menú y para consultar logs
#-----------------------------------------------------

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
    else
        echo "No se encontró dnsmasq en el sistema ni en Docker para consultar logs."
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
            if [[ "$log_source" == "system" ]]; then
                journalctl -u dnsmasq
            else
                docker logs "$container_id"
            fi
            ;;
        2)
            read -p "Ingrese la fecha de inicio (YYYY-MM-DD HH:MM:SS): " fecha_inicio
            if [[ "$log_source" == "system" ]]; then
                journalctl -u dnsmasq --since "$fecha_inicio"
            else
                docker logs "$container_id" --since "$fecha_inicio"
            fi
            ;;
        3)
            read -p "Ingrese la fecha final (YYYY-MM-DD HH:MM:SS): " fecha_fin
            if [[ "$log_source" == "system" ]]; then
                journalctl -u dnsmasq --until "$fecha_fin"
            else
                docker logs "$container_id" --until "$fecha_fin"
            fi
            ;;
        4)
            read -p "Ingrese la fecha de inicio (YYYY-MM-DD HH:MM:SS): " fecha_inicio
            read -p "Ingrese la fecha final (YYYY-MM-DD HH:MM:SS): " fecha_fin
            if [[ "$log_source" == "system" ]]; then
                journalctl -u dnsmasq --since "$fecha_inicio" --until "$fecha_fin"
            else
                docker logs "$container_id" --since "$fecha_inicio" --until "$fecha_fin"
            fi
            ;;
        5)
            read -p "Ingrese la cantidad de líneas a mostrar: " num_lineas
            if [[ "$log_source" == "system" ]]; then
                journalctl -u dnsmasq -n "$num_lineas"
            else
                docker logs "$container_id" --tail "$num_lineas"
            fi
            ;;
        6)
            read -p "Ingrese la prioridad a filtrar (ej: err, warning, info, debug): " prioridad
            if [[ "$log_source" == "system" ]]; then
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

#-----------------------------------------------------
# Funciones de gestión en el sistema
#-----------------------------------------------------

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

#-----------------------------------------------------
# Funciones de configuración en el sistema
#-----------------------------------------------------

cambiarPuertoSistema() {
    viejo_puerto=$(grep "^port=" /etc/dnsmasq.conf | cut -d'=' -f2)

    read -p "Ingrese el nuevo puerto: " nuevo_puerto
    if check_port "$nuevo_puerto"; then
        nuevo_puerto=$(resolve_port_conflict "$nuevo_puerto")
    fi

    if [[ "$viejo_puerto" != "$nuevo_puerto" ]]; then
        # Cerramos el puerto anterior y abrimos el nuevo
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

#-----------------------------------------------------
# Funciones de gestión en Docker
#-----------------------------------------------------

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

#-----------------------------------------------------
# Funciones de configuración en Docker
#-----------------------------------------------------

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
    docker run -d --name dnsmasq -p $nuevo_puerto:$nuevo_puerto/udp -p $nuevo_puerto:$nuevo_puerto/tcp \
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

    docker run -d --name dnsmasq \
        -p "$current_port:$current_port/udp" \
        -p "$current_port:$current_port/tcp" \
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

    docker run -d --name dnsmasq \
        --network host \
        --restart unless-stopped \
        -p "$current_port:$current_port/udp" \
        -p "$current_port:$current_port/tcp" \
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

    docker run -d --name dnsmasq \
        --network host \
        -p "$current_port:$current_port/udp" \
        -p "$current_port:$current_port/tcp" \
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

    docker run -d --name dnsmasq \
        --network host \
        -p "$current_port:$current_port/udp" \
        -p "$current_port:$current_port/tcp" \
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

    if [[ -f "$CONFIG_FILE" ]]; then
        current_port=$(grep "^port=" "$CONFIG_FILE" | cut -d'=' -f2)
        cerrarPuertoUFW "$current_port"
    fi

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


# Gestion dels ervicio
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

# Función auxiliar para (start|stop|restart) con Ansible
ansible_dnsmasq_service() {
    local desired_state=$1

    echo "Creando playbook para '$desired_state' dnsmasq en Ansible..."
    cat <<EOF > /tmp/dnsmasq_service.yml
---
- name: Gestionar servicio dnsmasq con Ansible
  hosts: localhost
  become: yes
  tasks:
    - name: Asegurar dnsmasq en estado '$desired_state'
      service:
        name: dnsmasq
        state: $desired_state
EOF

    echo "Ejecutando playbook de Ansible para '$desired_state' dnsmasq..."
    ansible-playbook /tmp/dnsmasq_service.yml

    echo "Operación '$desired_state' finalizada."
}

# Función para mostrar estado con Ansible (usando el módulo service o un shell)
ansible_dnsmasq_status() {
    echo "Creando playbook para consultar 'status' de dnsmasq..."
    cat <<EOF > /tmp/dnsmasq_status.yml
---
- name: Consultar estado de dnsmasq con Ansible
  hosts: localhost
  become: yes
  tasks:
    - name: Ver estado del servicio con systemd
      shell: systemctl status dnsmasq
      register: dnsmasq_status

    - name: Mostrar salida
      debug:
        var: dnsmasq_status.stdout
EOF

    echo "Ejecutando playbook de Ansible para consultar el estado..."
    ansible-playbook /tmp/dnsmasq_status.yml
}


# Config del servicio con ansible
configurarServicioAnsible() {
    echo -e "\nCONFIGURAR DNSMASQ (ANSIBLE)"
    echo "---------------------------------"
    echo "1) Cambiar puerto"
    echo "2) Cambiar dominio"
    echo "3) Cambiar interfaz"
    echo "4) Cambiar servidores DNS"
    echo "5) Añadir host"
    read -p "Seleccione una opción: " opcion
    case "$opcion" in
        1) ansible_cambiarPuerto ;;
        2) ansible_cambiarDominio ;;
        3) ansible_cambiarInterfaz ;;
        4) ansible_cambiarServidoresDNS ;;
        5) ansible_añadirHosts ;;
        *) echo "Opción no válida." ;;
    esac
}


ansible_cambiarPuerto() {
    read -p "Ingrese el nuevo puerto: " nuevo_puerto

    cat <<EOF > /tmp/dnsmasq_conf_port.yml
---
- name: Cambiar puerto dnsmasq via Ansible
  hosts: localhost
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

    ansible-playbook /tmp/dnsmasq_conf_port.yml
    echo "Se cambió el puerto a $nuevo_puerto."
}

ansible_cambiarDominio() {
    read -p "Ingrese el nuevo dominio: " nuevo_dominio
    [[ -z "$nuevo_dominio" ]] && nuevo_dominio="local"

    cat <<EOF > /tmp/dnsmasq_conf_domain.yml
---
- name: Cambiar dominio en /etc/dnsmasq.conf con Ansible
  hosts: localhost
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

    ansible-playbook /tmp/dnsmasq_conf_domain.yml
    echo "Se cambió el dominio a $nuevo_dominio."
}

ansible_cambiarInterfaz() {
    read -p "Ingrese la nueva interfaz (ej: eth0, ens33): " nueva_interfaz
    [[ -z "$nueva_interfaz" ]] && nueva_interfaz="ens33"

    cat <<EOF > /tmp/dnsmasq_conf_iface.yml
---
- name: Cambiar interfaz en /etc/dnsmasq.conf con Ansible
  hosts: localhost
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

    ansible-playbook /tmp/dnsmasq_conf_iface.yml
    echo "Se cambió la interfaz a $nueva_interfaz."
}

ansible_cambiarServidoresDNS() {
    read -p "Ingrese los nuevos servidores DNS (separados por espacios): " nuevos_dns

    cat <<EOF > /tmp/dnsmasq_conf_dns.yml
---
- name: Cambiar servidores DNS en /etc/dnsmasq.conf con Ansible
  hosts: localhost
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
      loop: 
$(printf "        - %s\n" $nuevos_dns)

    - name: Reiniciar dnsmasq
      service:
        name: dnsmasq
        state: restarted
EOF

    ansible-playbook /tmp/dnsmasq_conf_dns.yml
    echo "Servidores DNS actualizados a: $nuevos_dns."
}

ansible_añadirHosts() {
    read -p "Ingrese el nombre del host (ej: servidor.local): " nombre_host
    read -p "Ingrese la IP correspondiente: " ip_host

    cat <<EOF > /tmp/dnsmasq_conf_hosts.yml
---
- name: Añadir host en /etc/dnsmasq.conf con Ansible
  hosts: localhost
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

    ansible-playbook /tmp/dnsmasq_conf_hosts.yml
    echo "Se ha añadido el host $nombre_host con IP $ip_host."
}


# Eliminar dnsmasq con ansible
eliminarDnsmasqAnsible() {
    echo "Eliminando dnsmasq con Ansible..."
    cat <<EOF > /tmp/dnsmasq_remove.yml
---
- name: Eliminar dnsmasq con Ansible
  hosts: localhost
  become: yes
  tasks:
    - name: Detener el servicio dnsmasq si está activo
      service:
        name: dnsmasq
        state: stopped
      ignore_errors: true
    
    - name: Desinstalar paquete dnsmasq
      apt:
        name: dnsmasq
        state: absent
        purge: yes
        update_cache: yes
      ignore_errors: true

    - name: Eliminar /etc/dnsmasq.conf si existe
      file:
        path: /etc/dnsmasq.conf
        state: absent
      ignore_errors: true
EOF

    ansible-playbook /tmp/dnsmasq_remove.yml
    echo "dnsmasq ha sido eliminado via Ansible."
    exit 1
}


#=====================================================
# 9. INICIO DEL SCRIPT
#=====================================================

#-----------------------------------------------------
# Bloque principal de ejecución
#-----------------------------------------------------

# Verificar el estado de dnsmasq en el sistema y en Docker
check_dnsmasq_system
SYSTEM_STATUS=$?
check_dnsmasq_docker
DOCKER_STATUS=$?
check_dnsmasq_ansible
ANSIBLE_STATUS=$?

# Obtener la IP
IP_ADDRESS=$(get_ip_address)

# Si dnsmasq no está instalado ni en el sistema ni en Docker, preguntamos cómo instalarlo
if [[ $SYSTEM_STATUS -eq 1 && $DOCKER_STATUS -eq 1 && $ANSIBLE_STATUS -eq 1 ]]; then
    estadoSistema
    echo "Seleccione el método de instalación:"
    echo "---------------------------------"
    echo "1) APT (paquete del sistema)"
    echo "2) Docker (contenedor)"
    echo "3) Ansible"
    echo "0) Salir"
    read -p "Seleccione una opción (1/2/0): " metodo
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

# Menú dinámico según dónde esté instalado
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


# Bucle del menú principal
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
