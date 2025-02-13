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

# Función para verificar si dnsmasq está corriendo en Docker
check_dnsmasq_docker() {
    if docker ps --format "{{.Image}}" | grep -q "dnsmasq"; then
        echo "dnsmasq está corriendo en un contenedor Docker."
        return 0
    else
        echo "dnsmasq NO está corriendo en Docker."
        return 1
    fi
}

# Verificar
check_dnsmasq_system
SYSTEM_STATUS=$?

check_dnsmasq_docker
DOCKER_STATUS=$?

# Si dnsmasq no está en el sistema ni en Docker, preguntar si instalarlo
if [[ $SYSTEM_STATUS -ne 0 && $DOCKER_STATUS -ne 0 ]]; then
    read -p "¿Desea instalar dnsmasq en el sistema? (s/n): " opt
    case "$opt" in
        s|S|si|Si|SI)
            echo "Instalando dnsmasq en el sistema..."
            ;;
        n|N|no|No|NO)
            echo "Instalación cancelada."
            exit 1
            ;;
        *)
            echo "Opción no válida. Adiós!"
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

# Función para gestionar el servicio de dnsmasq
function gestionarServicio() {
    echo "---------------------------------"
    echo "  MENÚ DE GESTIÓN DEL SERVICIO  "
    echo "---------------------------------"
    echo "1. Iniciar"
    echo "2. Detener"
    echo "3. Reiniciar"
    echo "4. Estado"
    read -p "Seleccione una acción para dnsmasq: " opcionGestion

    case "$opcionGestion" in
        1) echo "Iniciando dnsmasq..."
           sudo systemctl start dnsmasq
           ;;
        2) echo "Deteniendo dnsmasq..."
           sudo systemctl stop dnsmasq
           ;;
        3) echo "Reiniciando dnsmasq..."
           sudo systemctl restart dnsmasq
           ;;
        4) echo "Estado del servicio dnsmasq:"
           sudo systemctl status dnsmasq
           ;;
        *) echo "Opción no válida."
           ;;
    esac
}

# Mostrar menú y leer la opción del usuario
while true; do
    mostrarMenu
    read -p "Seleccione una opción: " opcionMenu
    case "$opcionMenu" in
        1) gestionarServicio ;;
        2) echo "Funcionalidad para añadir registro DNS (pendiente de implementación)" ;;
        3) echo "Eliminando dnsmasq..."
           sudo apt remove --purge -y dnsmasq
           sudo rm -rf /etc/dnsmasq.conf
           echo "✅ dnsmasq ha sido eliminado correctamente."
           ;;
        0) echo "Saliendo..."
           exit 0
           ;;
        *) echo "Opción no válida. Intente de nuevo." ;;
    esac
done
