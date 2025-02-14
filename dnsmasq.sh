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
        return 0  # Contenedor en ejecución
    elif [[ -n "$CONTAINER_EXISTS" ]]; then
        return 2  # Contenedor detenido
    elif [[ -n "$IMAGE_EXISTS" ]]; then
        return 3  # Imagen disponible pero sin contenedor
    else
        return 1  # No está en Docker
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
    echo "-----------------------------------------------------"
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
            echo "dnsmasq instalado correctamente en el sistema operativo."
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
MENU_OPCION_2="Consultar logs (no implementado)"
MENU_OPCION_3="Configurar el servicio (no implementado)"
MENU_OPCION_4=""
MENU_FUNCION_1=""
MENU_FUNCION_2="consultarLogs"
MENU_FUNCION_3="configurarServicio"
MENU_FUNCION_4=""

if [[ $SYSTEM_STATUS -eq 0 ]]; then
    MENU_OPCION_1="Gestionar dnsmasq (Sistema)"
    MENU_OPCION_4="Eliminar dnsmasq del sistema"
    MENU_FUNCION_1="gestionarServicioSistema"
    MENU_FUNCION_4="eliminarDnsmasqSistema"
fi
if [[ $DOCKER_STATUS -ne 1 ]]; then
    MENU_OPCION_1="Gestionar dnsmasq (Docker)"
    MENU_OPCION_4="Eliminar dnsmasq de Docker"
    MENU_FUNCION_1="gestionarServicioDocker"
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
    echo "dnsmasq ha sido eliminado del sistema."
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
        2) docker stop "$CONTAINER_ID" && docker rm "$CONTAINER_ID" && docker rmi diego57709/dnsmasq:latest && echo "Imagen eliminada correctamente." ;;
        0) return ;;
        *) echo "Opción no válida." ;;
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
