#!/bin/bash

# Función para verificar si dnsmasq está instalado en el sistema
check_dnsmasq_system() {
    if dpkg -l | grep -qw dnsmasq && systemctl list-unit-files | grep -q "dnsmasq.service"; then
        echo "dnsmasq está instalado en el sistema operativo y el servicio está disponible."
        return 0
    else
        echo "dnsmasq NO está instalado en el sistema o el servicio no está disponible."
        return 1
    fi
}

# Función para verificar si dnsmasq está en Docker (corriendo o detenido)
check_dnsmasq_docker() {
    CONTAINER_RUNNING=$(docker ps -q --filter "ancestor=diego57709/dnsmasq")
    CONTAINER_EXISTS=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
    IMAGE_EXISTS=$(docker images -q diego57709/dnsmasq)

    if [[ -n "$CONTAINER_RUNNING" ]]; then
        echo "dnsmasq está corriendo en un contenedor Docker."
        return 0
    elif [[ -n "$CONTAINER_EXISTS" ]]; then
        echo "dnsmasq está en Docker pero el contenedor está detenido."
        return 2 
    elif [[ -n "$IMAGE_EXISTS" ]]; then
        echo "dnsmasq está en Docker como imagen, pero no hay contenedor creado."
        return 3
    else
        echo "dnsmasq NO está en Docker."
        return 1
}

# Verificar si dnsmasq está en el sistema o en Docker
check_dnsmasq_system
SYSTEM_STATUS=$?

check_dnsmasq_docker
DOCKER_STATUS=$?

# Si dnsmasq no está en el sistema ni en Docker, preguntar si instalarlo
if [[ $SYSTEM_STATUS -ne 0 && $DOCKER_STATUS -eq 1 ]]; then
    read -p "¿Desea instalar dnsmasq en Docker? (s/n): " opt
    case "$opt" in
        s|S|si|Si|SI)
            echo "Instalando dnsmasq en Docker..."
            docker pull diego57709/dnsmasq:latest
            docker run -d --name dnsmasq-5354 -p 5354:5354/udp -p 5354:5354/tcp diego57709/dnsmasq:latest
            echo "dnsmasq ha sido instalado correctamente."
            ;;
        n|N|no|No|NO)
            echo "Instalación cancelada."
            exit 1
            ;;
        *)
            echo "Opción no válida. Adiós."
            exit 1
            ;;
    esac
fi

# Función para mostrar el menú principal
function mostrarMenu() {
    echo "---------------------------------"
    echo "  MENÚ DE DNSMASQ (0-3)  "
    echo "---------------------------------"
    echo "1. Gestionar el servicio"
    echo "2. Añadir registro DNS"
    echo "3. Borrar el servicio"
    echo "0. Salir"
}

# Función para gestionar el servicio de dnsmasq en el sistema o Docker
function gestionarServicio() {
    echo "---------------------------------"
    echo "  MENÚ DE GESTIÓN DEL SERVICIO  "
    echo "---------------------------------"
    echo "1. Iniciar"
    echo "2. Detener"
    echo "3. Reiniciar"
    echo "4. Estado"
    read -p "Seleccione una acción para dnsmasq: " opcionGestion

    if [[ $SYSTEM_STATUS -eq 0 ]]; then
        case "$opcionGestion" in
            1) sudo systemctl start dnsmasq && echo "Servicio iniciado con éxito." || echo "Error al iniciar el servicio." ;;
            2) sudo systemctl stop dnsmasq && echo "Servicio detenido con éxito." || echo "Error al detener el servicio." ;;
            3) sudo systemctl restart dnsmasq && echo "Servicio reiniciado con éxito." || echo "Error al reiniciar el servicio." ;;
            4) sudo systemctl --no-pager status dnsmasq || echo "Error al obtener el estado del servicio." ;;
            *) echo "Opción no válida." ;;
        esac
    elif [[ $DOCKER_STATUS -eq 0 ]]; then
        # Gestionar dnsmasq en Docker
        CONTAINER_ID=$(docker ps -q --filter "ancestor=diego57709/dnsmasq")
        case "$opcionGestion" in
            1) echo "El contenedor ya está en ejecución." ;;
            2) docker stop $CONTAINER_ID && echo "Contenedor detenido con éxito." || echo "Error al detener el contenedor." ;;
            3) docker restart $CONTAINER_ID && echo "Contenedor reiniciado con éxito." || echo "Error al reiniciar el contenedor." ;;
            4) docker ps --filter "id=$CONTAINER_ID" --format "ID: {{.ID}}, Estado: {{.Status}}" ;;
            *) echo "Opción no válida." ;;
        esac
    elif [[ $DOCKER_STATUS -eq 2 ]]; then
        # Contenedor existe pero está detenido → permitir iniciarlo
        CONTAINER_ID=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
        case "$opcionGestion" in
            1) docker start $CONTAINER_ID && echo "Contenedor iniciado con éxito." || echo "Error al iniciar el contenedor." ;;
            2) echo "El contenedor ya está detenido." ;;
            3) docker restart $CONTAINER_ID && echo "Contenedor reiniciado con éxito." || echo "Error al reiniciar el contenedor." ;;
            4) docker ps --filter "id=$CONTAINER_ID" --format "ID: {{.ID}}, Estado: {{.Status}}" ;;
            *) echo "Opción no válida." ;;
        esac
    else
        echo "No se detecta dnsmasq ni en el sistema ni en Docker."
    fi
}

# Mostrar menú y leer la opción del usuario
while true; do
    mostrarMenu
    read -p "Seleccione una opción: " opcionMenu
    case "$opcionMenu" in
        1) gestionarServicio ;;
        2) echo "Funcionalidad para añadir registro DNS (pendiente de implementación)." ;;
        3) eliminarServicio ;;
        0) echo "Saliendo..."
           exit 0
           ;;
        *) echo "Opción no válida. Intente de nuevo." ;;
    esac
done
