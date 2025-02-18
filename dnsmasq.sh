#!/bin/bash
#-----------------------------------------------------
# Funciones generales
#-----------------------------------------------------

# Función para obtener la IP del equipo
get_ip_address() {
    IP=$(hostname -I | awk '{print $1}')
    echo "$IP"
}

# Función para verificar si dnsmasq está instalado en el sistema (APT)
check_dnsmasq_system() {
    if dpkg -l | grep -qw dnsmasq && systemctl list-unit-files | grep -q "dnsmasq.service"; then
        return 0  # Instalado en el sistema
    else
        return 1  # No instalado en el sistema
    fi
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

# Función para ver si esta usandose un puerto
check_port() {
    local port=$1
    if ss -tuln | grep -E -q ":${port}($|[^0-9])"; then
        return 0  # En uso
    else
        return 1  # Libre
    fi
}

# Función para arreglar el conflicto del puerto
resolve_port_conflict() {
    local current_port=$1
    while true; do
        read -p "El puerto $current_port está en uso. Ingrese un nuevo puerto: " new_port
        if ! check_port "$new_port"; then
            echo "$new_port"
            return
        else
            echo "El puerto $new_port también está en uso. Intente con otro."
        fi
    done
}

# Función para mostrar el estado actual del sistema
estadoSistema() {
    echo "-----------------------------------------------------"
    echo " Estado actual del sistema"
    echo "-----------------------------------------------------"
    echo "IP del equipo: $(get_ip_address)"
    if [[ $SYSTEM_STATUS -eq 0 ]]; then
        echo "dnsmasq está instalado en el sistema operativo."
    else
        echo "dnsmasq NO está instalado en el sistema operativo."
    fi
    if [[ $DOCKER_STATUS -eq 0 ]]; then
        echo "dnsmasq está corriendo en un contenedor Docker."
    elif [[ $DOCKER_STATUS -eq 2 ]]; then
        echo "dnsmasq está en Docker pero el contenedor está detenido."
    elif [[ $DOCKER_STATUS -eq 3 ]]; then
        echo "dnsmasq está en Docker como imagen, pero no hay contenedor creado."
    else
        echo "dnsmasq NO está en Docker."
    fi
}

#-----------------------------------------------------
# Funciones de instalación
#-----------------------------------------------------

# Función para instalar dnsmasq mediante APT (paquete del sistema)
instalar_dnsmasq_apt() {
    echo "Instalando dnsmasq con APT..."
    sudo apt update && sudo apt install -y dnsmasq

    echo ""
    echo "Seleccione el tipo de configuración a aplicar:"
    echo "1) Configuración básica (Puerto 53, dominio 'local', interfaz 'lo', DNS 8.8.8.8)"
    echo "2) Configuración personalizada"
    read -p "Opción (1/2): " opcion_config

    if [[ "$opcion_config" == "1" ]]; then
        puerto=53
        dominio="local"
        interfaz="lo"
        servidores_dns="8.8.8.8"
    elif [[ "$opcion_config" == "2" ]]; then
        read -p "Puerto (ej: 53): " puerto
        [[ -z "$puerto" ]] && puerto=53
        read -p "Dominio (ej: local): " dominio
        [[ -z "$dominio" ]] && dominio="local"
        read -p "Interfaz (ej: lo, eth0, ens33): " interfaz
        [[ -z "$interfaz" ]] && interfaz="lo"
        read -p "Servidores DNS (ej: 8.8.8.8 1.1.1.1): " servidores_dns
        [[ -z "$servidores_dns" ]] && servidores_dns="8.8.8.8"
    else
        echo "Opción no válida. Se aplicará la configuración básica por defecto."
        puerto=53
        dominio="local"
        interfaz="lo"
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
EOF
    for dns in $servidores_dns; do
        echo "server=$dns" | sudo tee -a /etc/dnsmasq.conf > /dev/null
    done

    echo "dnsmasq instalado y configurado en el sistema (APT)."
    sudo systemctl restart dnsmasq
}

# Función para instalar dnsmasq con Docker
instalar_dnsmasq_docker() {
    echo "Instalando dnsmasq en Docker..."
    docker pull diego57709/dnsmasq:latest
    mkdir -p ~/dnsmasq-docker

    echo "Seleccione el tipo de configuración:"
    echo "1) Configuración básica (Puerto 53, interfaz 'eth0', DNS 8.8.8.8)"
    echo "2) Configuración personalizada"
    read -p "Opción (1/2): " opcion_config

    CONFIG_FILE=~/dnsmasq-docker/dnsmasq.conf

    if [[ "$opcion_config" == "1" ]]; then
        puerto=53
        interfaz="eth0"
        servidores_dns="8.8.8.8"
    elif [[ "$opcion_config" == "2" ]]; then
        read -p "Puerto (ej: 53): " puerto
        [[ -z "$puerto" ]] && puerto=53
        read -p "Interfaz (ej: eth0, ens33): " interfaz
        [[ -z "$interfaz" ]] && interfaz="eth0"
        read -p "Servidores DNS (ej: 8.8.8.8 1.1.1.1): " servidores_dns
        [[ -z "$servidores_dns" ]] && servidores_dns="8.8.8.8"
    else
        echo "Opción no válida. Se aplicará la configuración básica por defecto."
        puerto=53
        interfaz="eth0"
        servidores_dns="8.8.8.8"
    fi

    # Verificar que fufa el puerto
    if check_port "$puerto"; then
        nuevo_puerto=$(resolve_port_conflict "$puerto")
        puerto=$nuevo_puerto
    fi

    echo "Generando archivo de configuración en $CONFIG_FILE..."
    tee $CONFIG_FILE > /dev/null <<EOF
# Configuración de dnsmasq para Docker
port=$puerto
interface=$interfaz
EOF
    for dns in $servidores_dns; do
        echo "server=$dns" | tee -a $CONFIG_FILE > /dev/null
    done

    docker run -d --name dnsmasq -p $puerto:$puerto/udp -p $puerto:$puerto/tcp \
        -v ~/dnsmasq-docker/dnsmasq.conf:/etc/dnsmasq.conf \
        diego57709/dnsmasq:latest

    echo "dnsmasq instalado en Docker con configuración en el puerto $puerto."
}

#-----------------------------------------------------
# Funciones para el menú
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

eliminarDnsmasqSistema() {
    echo "Eliminando dnsmasq del sistema..."
    sudo systemctl stop dnsmasq
    sudo apt remove -y dnsmasq
    sudo apt autoremove -y
    echo "dnsmasq ha sido eliminado del sistema."
    exit 1
}

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

eliminarDnsmasqDocker() {
    CONTAINER_ID=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
    echo -e "\nELIMINAR DNSMASQ EN DOCKER"
    echo "---------------------------------"
    echo "1) Borrar solo el contenedor"
    echo "2) Borrar contenedor e imagen"
    echo "0) Volver al menú"
    read -p "Seleccione una opción: " opcion
    case "$opcion" in
        1) docker stop "$CONTAINER_ID" && docker rm "$CONTAINER_ID" && echo "Contenedor eliminado correctamente." ;;
        2) docker stop "$CONTAINER_ID" && docker rm "$CONTAINER_ID" && docker rmi diego57709/dnsmasq:latest && echo "Imagen eliminada correctamente." && exit 1 ;;
        0) return ;;
        *) echo "Opción no válida." ;;
    esac
}

#-----------------------------------------------------
# Inicio del Script
#-----------------------------------------------------

# Verificar el estado de dnsmasq en el sistema y en Docker
check_dnsmasq_system
SYSTEM_STATUS=$?
check_dnsmasq_docker
DOCKER_STATUS=$?

# Obtener la IP
IP_ADDRESS=$(get_ip_address)

# Si dnsmasq no está instalado ni en el sistema ni en Docker, preguntamos como quiere instalarlo
if [[ $SYSTEM_STATUS -eq 1 && $DOCKER_STATUS -eq 1 ]]; then
    estadoSistema
    echo "Seleccione el método de instalación:"
    echo "1) APT (paquete del sistema)"
    echo "2) Docker (contenedor)"
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

# Menú dinamico que depende donde este intslado
if [[ $SYSTEM_STATUS -eq 0 ]]; then
    MENU_OPCION_1="Gestionar dnsmasq (Sistema)"
    MENU_OPCION_2="Consultar logs"
    MENU_OPCION_3="Configurar el servicio (no implementado)"
    MENU_OPCION_4="Eliminar dnsmasq del sistema"
    MENU_FUNCION_1="gestionarServicioSistema"
    MENU_FUNCION_2="consultarLogs"
    MENU_FUNCION_4="eliminarDnsmasqSistema"
fi
if [[ $DOCKER_STATUS -ne 1 ]]; then
    MENU_OPCION_1="Gestionar dnsmasq (Docker)"
    MENU_OPCION_2="Consultar logs"
    MENU_OPCION_3="Configurar el servicio (no implementado)"
    MENU_OPCION_4="Eliminar dnsmasq de Docker"
    MENU_FUNCION_1="gestionarServicioDocker"
    MENU_FUNCION_2="consultarLogs"
    MENU_FUNCION_4="eliminarDnsmasqDocker"
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
