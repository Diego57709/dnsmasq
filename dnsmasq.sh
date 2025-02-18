#!/bin/bash

# Función para obtener la IP del equipo
get_ip_address() {
    IP=$(hostname -I | awk '{print $1}')
    echo "$IP"
}

# Función para verificar si dnsmasq está instalado en el sistema
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

# Verificar estado de dnsmasq en el sistema y en Docker
check_dnsmasq_system
SYSTEM_STATUS=$?
check_dnsmasq_docker
DOCKER_STATUS=$?

# Obtener la IP del equipo
IP_ADDRESS=$(get_ip_address)

function estadoSistema () {
    # Mostrar el estado al inicio del script
    echo "-----------------------------------------------------"
    echo " Estado actual del sistema"
    echo "-----------------------------------------------------"
    echo "IP del equipo: $IP_ADDRESS"

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

# Si dnsmasq no está en ningún lado, preguntar método de instalación
if [[ $SYSTEM_STATUS -eq 1 && $DOCKER_STATUS -eq 1 ]]; then
    estadoSistema
    echo "Seleccione el método de instalación:"
    echo "1) APT (paquete del sistema)"
    echo "2) Docker (contenedor)"
    echo "0) Salir (contenedor)"
    read -p "Seleccione una opción (1/2): " metodo

    case "$metodo" in
        1)
            echo "Instalando dnsmasq con APT..."
            sudo apt update && sudo apt install -y dnsmasq

            echo ""
            echo "Seleccione el tipo de configuración que desea aplicar:"
            echo "1) Configuración básica (Puerto 53, dominio local, interfaz lo, DNS 8.8.8.8)"
            echo "2) Configuración personalizada (Se le solicitará cada parámetro)"
            read -p "Opción (1/2): " opcion_config

            if [[ "$opcion_config" == "1" ]]; then
                echo "Generando configuración básica..."
                sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
# Configuración básica de dnsmasq
port=5354
domain=juanpepeloko
interface=ens33
server=8.8.8.8
EOF
                echo "Se ha aplicado la configuración básica en /etc/dnsmasq.conf."

            elif [[ "$opcion_config" == "2" ]]; then
                echo "Ingrese los parámetros de configuración personalizada:"

                read -p "Puerto (ej: 5354): " puerto
                [[ -z "$puerto" ]] && puerto=5354

                read -p "Dominio (ej: juanpepeloko): " dominio
                [[ -z "$dominio" ]] && dominio="juanpepeloko"

                read -p "Interfaz (ej: lo, eth0, ens33): " interfaz
                [[ -z "$interfaz" ]] && interfaz="ens33"

                read -p "Servidores DNS (ej: 8.8.8.8 1.1.1.1): " servidores_dns
                [[ -z "$servidores_dns" ]] && servidores_dns="8.8.8.8"

                echo "Generando configuración personalizada..."
                sudo tee /etc/dnsmasq.conf > /dev/null <<EOF
# Configuración personalizada de dnsmasq
port=$puerto
domain=$dominio
interface=$interfaz
EOF

                for dns in $servidores_dns; do
                    echo "server=$dns" | sudo tee -a /etc/dnsmasq.conf > /dev/null
                done

                echo "Se ha aplicado la configuración personalizada en /etc/dnsmasq.conf."
            else
                echo "Opción no válida. Se aplicará la configuración básica por defecto."
                sudo tee /etc/dnsmasq.conf > /dev/null <<-EOF
# Configuración básica de dnsmasq
port=5354
domain=juanpepeloko
interface=ens33
server=8.8.8.8
EOF
                echo "Se ha aplicado la configuración básica en /etc/dnsmasq.conf."
            fi

            echo "dnsmasq instalado y configurado correctamente en el sistema operativo."
            sudo systemctl restart dnsmasq
            SYSTEM_STATUS=0

            ;;
        2)
            echo "Instalando dnsmasq en Docker..."
            docker pull diego57709/dnsmasq:latest
            docker run -d --name dnsmasq-5354 -p 5354:5354/udp -p 5354:5354/tcp diego57709/dnsmasq:latest
            echo "dnsmasq ha sido instalado correctamente en Docker."
            DOCKER_STATUS=0
            ;;
        3)
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo "Opción no válida. Adiós."
            exit 1
            ;;
    esac
fi

# Configuración dinámica de opciones del menú
MENU_OPCION_1=""
MENU_OPCION_2=""
MENU_OPCION_3="Configurar el servicio (no implementado)"
MENU_OPCION_4=""
MENU_FUNCION_1=""
MENU_FUNCION_2=""
MENU_FUNCION_3="configurarServicio"
MENU_FUNCION_4=""

if [[ $SYSTEM_STATUS -eq 0 ]]; then
    MENU_OPCION_1="Gestionar dnsmasq (Sistema)"
    MENU_OPCION_2="Consultar logs"
    MENU_OPCION_4="Eliminar dnsmasq del sistema"
    MENU_FUNCION_1="gestionarServicioSistema"
    MENU_FUNCION_2="consultarLogs"
    MENU_FUNCION_4="eliminarDnsmasqSistema"
fi
if [[ $DOCKER_STATUS -ne 1 ]]; then
    MENU_OPCION_1="Gestionar dnsmasq (Docker)"
    MENU_OPCION_2="Consultar logs"
    MENU_OPCION_4="Eliminar dnsmasq de Docker"
    MENU_FUNCION_1="gestionarServicioDocker"
    MENU_FUNCION_2="consultarLogs"
    MENU_FUNCION_4="eliminarDnsmasqDocker"
fi

# Función para mostrar el menú
function mostrarMenu() {
    echo -e "\nMENÚ DE DNSMASQ"
    echo "---------------------------------"
    echo "1) $MENU_OPCION_1"
    echo "2) $MENU_OPCION_2"
    echo "3) $MENU_OPCION_3"
    echo "4) $MENU_OPCION_4"
    echo "0) Salir"
}

# Función para consultar logs (Placeholder)
function consultarLogs() {
    echo "Funcionalidad pendiente de implementación."
}

# Función para gestionar dnsmasq en el sistema
function gestionarServicioSistema() {
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

# Función para eliminar dnsmasq del sistema
function eliminarDnsmasqSistema() {
    echo "Eliminando dnsmasq del sistema..."
    sudo systemctl stop dnsmasq
    sudo apt remove -y dnsmasq
    sudo apt autoremove -y
    echo "dnsmasq ha sido eliminado del sistema." && exit 1

}


# Función para gestionar dnsmasq en Docker
function gestionarServicioDocker() {
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

# Función para eliminar dnsmasq de Docker
function eliminarDnsmasqDocker() {
    CONTAINER_ID=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")

    echo -e "\nELIMINAR DNSMASQ EN DOCKER"
    echo "---------------------------------"
    echo "1  Borrar solo el contenedor"
    echo "2  Borrar contenedor e imagen"
    echo "0  Volver al menú"
    read -p "Seleccione una opción: " opcion

    case "$opcion" in
        1) docker stop "$CONTAINER_ID" && docker rm "$CONTAINER_ID" && echo "Contenedor eliminado correctamente." ;;
        2) docker stop "$CONTAINER_ID" && docker rm "$CONTAINER_ID" && docker rmi diego57709/dnsmasq:latest && echo "Imagen eliminada correctamente." && exit 1;;
        0) return ;;
        *) echo "Opción no válida." ;;
    esac
}

# Función para consultar logs con distintos filtros
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
        echo "No se encontró dnsmasq ni en el sistema ni en Docker para consultar logs."
        return
    fi

    echo ""
    echo "Seleccione la opción de filtrado:"
    echo "1) Mostrar TODOS los logs"
    echo "2) Mostrar logs DESDE una fecha (formato: YYYY-MM-DD HH:MM:SS)"
    echo "3) Mostrar logs HASTA una fecha (formato: YYYY-MM-DD HH:MM:SS)"
    echo "4) Mostrar logs en un RANGO de fechas (desde y hasta)"
    echo "5) Mostrar las últimas N líneas (ej: 10, 20, 30)"
    echo "6) Mostrar logs por PRIORIDAD (ej: err, warning, info, debug)"
    read -p "Opción: " filtro_opcion

    case "$filtro_opcion" in
        1)
            # Mostrar todos los logs
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
            read -p "Ingrese la cantidad de líneas a mostrar (ej: 10, 20, 30): " num_lineas
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

# Bucle del menú
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
