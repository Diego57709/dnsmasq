#!/bin/bash

check_dnsmasq_system() {
    if dpkg -l | grep -qw dnsmasq && systemctl list-unit-files | grep -q "dnsmasq.service"; then
        echo "dnsmasq está instalado en el sistema operativo y el servicio está disponible."
        return 0
    else
        echo "dnsmasq NO está instalado en el sistema o el servicio no está disponible."
        return 1
    fi
}

check_dnsmasq_docker() {
    if docker ps --format "{{.Image}}" | grep -q "dnsmasq"; then
        echo "dnsmasq está corriendo en un contenedor Docker."
        return 0
    else
        echo "dnsmasq NO está corriendo en Docker."
        return 1
    fi
}

check_dnsmasq_system
SYSTEM_STATUS=$?

check_dnsmasq_docker
DOCKER_STATUS=$?

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
            echo "Opción no válida. Adios!"
            exit 1
            ;;
    esac
fi
