#!/bin/bash
set -euo pipefail

# Función para mostrar mensaje de error y salir del script
error_exit() {
    echo -e "[ERROR] $1" >&2
    exit 1
}

# Capturar señales de interrupción o error inesperado
trap 'error_exit "El script fue interrumpido o se produjo un error inesperado."' SIGINT SIGTERM ERR

# Función para comprobar el estado de dnsmasq en Docker
check_dnsmasq_docker() {
    # Buscar contenedor en ejecución basado en la imagen
    CONTAINER_RUNNING=$(docker ps -q --filter "ancestor=diego57709/dnsmasq") || error_exit "Error al consultar contenedores en ejecución."
    # Buscar si está el contenedor (aunque esté detenido)
    CONTAINER_EXISTS=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq") || error_exit "Error al consultar contenedores existentes."
    # Verificar si existe la imagen
    IMAGE_EXISTS=$(docker images -q "diego57709/dnsmasq") || error_exit "Error al verificar la imagen de dnsmasq."

    if [[ -n "$CONTAINER_RUNNING" ]]; then
        echo -e "dnsmasq está corriendo en un contenedor Docker."
        return 0
    elif [[ -n "$CONTAINER_EXISTS" ]]; then
        echo -e "dnsmasq está en Docker pero el contenedor está detenido."
        return 2
    elif [[ -n "$IMAGE_EXISTS" ]]; then
        echo -e "dnsmasq está en Docker como imagen, pero no hay contenedor creado."
        return 3
    else
        echo -e "dnsmasq NO está en Docker."
        return 1
    fi
}

# Verificar el estado de dnsmasq en Docker al iniciar el script
check_dnsmasq_docker
DOCKER_STATUS=$?

# Si dnsmasq no está presente, preguntar al usuario si desea instalarlo
if [[ $DOCKER_STATUS -eq 1 ]]; then
    read -p "¿Desea instalar dnsmasq en Docker? (s/n): " opt
    case "$opt" in
        s|S|si|Si|SI)
            echo -e "Instalando dnsmasq en Docker..."
            docker pull diego57709/dnsmasq:latest || error_exit "Error al descargar la imagen."
            docker run -d --name dnsmasq-5354 -p 5354:5354/udp -p 5354:5354/tcp diego57709/dnsmasq:latest || error_exit "Error al crear el contenedor."
            echo -e "dnsmasq ha sido instalado correctamente."
            ;;
        n|N|no|No|NO)
            echo -e "Instalación cancelada."
            exit 1
            ;;
        *)
            echo -e "Opción no válida. Adiós."
            exit 1
            ;;
    esac
fi

# Función para mostrar los datos de red del equipo
mostrar_datos_red() {
    echo -e "\n=== DATOS DE RED ==="
    # Mostrar la configuración de red (ip o ifconfig)
    ip addr show || ifconfig || echo "No se pudo obtener información de red."
    echo -e "====================="
}

# Función para mostrar el estado del servicio (dnsmasq)
estado_servicio() {
    echo -e "\n=== ESTADO DEL SERVICIO (dnsmasq) ==="
    docker ps --filter "ancestor=diego57709/dnsmasq" --format "ID: {{.ID}}, Estado: {{.Status}}" || echo "No se encontró el servicio."
    echo -e "======================================="
}

# Función para instalar el servicio en Docker
instalar_servicio() {
    check_dnsmasq_docker
    DOCKER_STATUS=$?
    if [[ $DOCKER_STATUS -eq 1 ]]; then
        echo -e "dnsmasq no está presente en Docker."
        read -p "¿Desea instalar dnsmasq en Docker? (s/n): " opt
        case "$opt" in
            s|S|si|Si|SI)
                echo -e "Instalando dnsmasq en Docker..."
                docker pull diego57709/dnsmasq:latest || error_exit "Error al descargar la imagen de dnsmasq."
                docker run -d --name dnsmasq-5354 -p 5354:5354/udp -p 5354:5354/tcp diego57709/dnsmasq:latest || error_exit "Error al crear/iniciar el contenedor."
                echo -e "dnsmasq ha sido instalado correctamente."
                ;;
            n|N|no|No|NO)
                echo -e "Instalación cancelada."
                ;;
            *)
                echo -e "Opción no válida. Cancelando."
                ;;
        esac
    else
        echo -e "dnsmasq ya se encuentra instalado en Docker."
    fi
}

# Función para gestionar el servicio (iniciar, detener, reiniciar, consultar estado)
gestionar_servicio() {
    echo -e "\nMENÚ DE GESTIÓN DEL SERVICIO"
    echo "---------------------------------"
    echo "1  Iniciar"
    echo "2  Detener"
    echo "3  Reiniciar"
    echo "4  Estado"
    read -p "Seleccione una opción: " opcionGestion

    # Verificar nuevamente el estado de dnsmasq en Docker
    check_dnsmasq_docker
    DOCKER_STATUS=$?

    if [[ $DOCKER_STATUS -eq 0 ]]; then
        # Si el contenedor está en ejecución, obtener su ID
        CONTAINER_ID=$(docker ps -q --filter "ancestor=diego57709/dnsmasq")
        case "$opcionGestion" in
            1)
                echo -e "El contenedor ya está en ejecución."
                ;;
            2)
                docker stop "$CONTAINER_ID" && echo -e "Contenedor detenido con éxito." || echo -e "Error al detener el contenedor."
                ;;
            3)
                docker restart "$CONTAINER_ID" && echo -e "Contenedor reiniciado con éxito." || echo -e "Error al reiniciar el contenedor."
                ;;
            4)
                docker ps --filter "id=$CONTAINER_ID" --format "ID: {{.ID}}, Estado: {{.Status}}"
                ;;
            *)
                echo -e "Opción no válida."
                ;;
        esac
    elif [[ $DOCKER_STATUS -eq 2 ]]; then
        # Si el contenedor existe pero está detenido, obtener su ID
        CONTAINER_ID=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
        case "$opcionGestion" in
            1)
                docker start "$CONTAINER_ID" && echo -e "Contenedor iniciado con éxito." || echo -e "Error al iniciar el contenedor."
                ;;
            2)
                echo -e "El contenedor ya está detenido."
                ;;
            3)
                docker restart "$CONTAINER_ID" && echo -e "Contenedor reiniciado con éxito." || echo -e "Error al reiniciar el contenedor."
                ;;
            4)
                docker ps --filter "id=$CONTAINER_ID" --format "ID: {{.ID}}, Estado: {{.Status}}"
                ;;
            *)
                echo -e "Opción no válida."
                ;;
        esac
    elif [[ $DOCKER_STATUS -eq 3 ]]; then
        # Si solo existe la imagen sin contenedor
        case "$opcionGestion" in
            1)
                docker run -d --name dnsmasq-5354 -p 5354:5354/udp -p 5354:5354/tcp diego57709/dnsmasq:latest \
                && echo -e "Contenedor creado e iniciado con éxito." \
                || echo -e "Error al crear/iniciar el contenedor."
                ;;
            *)
                echo -e "Opción no válida. Solo se permite iniciar el contenedor cuando no existe."
                ;;
        esac
    else
        echo -e "No se detecta dnsmasq en Docker."
    fi
}

# Función para eliminar el servicio
eliminar_servicio() {
    echo -e "\nELIMINAR DNSMASQ EN DOCKER"
    echo "---------------------------------"
    echo "1  Borrar solo el contenedor"
    echo "2  Borrar contenedor e imagen"
    echo "0  Volver al menú"
    read -p "Seleccione una opción: " opcionBorrar

    # Obtener el ID del contenedor basado en la imagen
    CONTAINER_ID=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")

    case "$opcionBorrar" in
        1)
            if [[ -n "$CONTAINER_ID" ]]; then
                echo -e "Eliminando solo el contenedor..."
                docker stop "$CONTAINER_ID"
                docker rm "$CONTAINER_ID"
                echo -e "Contenedor eliminado correctamente."
            else
                echo -e "No se encontró un contenedor de dnsmasq para eliminar."
            fi
            ;;
        2)
            if [[ -n "$CONTAINER_ID" ]]; then
                echo -e "Eliminando contenedor e imagen de dnsmasq..."
                docker stop "$CONTAINER_ID"
                docker rm "$CONTAINER_ID"
            fi
            if [[ -n "$(docker images -q diego57709/dnsmasq)" ]]; then
                docker rmi diego57709/dnsmasq:latest || error_exit "Error al eliminar la imagen."
                echo -e "Imagen eliminada correctamente."
                exit 1
            else
                echo -e "No se encontró la imagen de dnsmasq."
            fi
            ;;
        0)
            echo -e "Volviendo al menú..."
            return
            ;;
        *)
            echo -e "Opción no válida."
            ;;
    esac
}

# Función para consultar los logs del servicio
consultar_logs() {
    echo -e "\nCONSULTAR LOGS"
    echo "---------------------------------"
    echo "a) Logs por fecha"
    echo "b) Logs completos"
    read -p "Seleccione una opción: " log_opcion
    case "$log_opcion" in
        a)
            echo -e "Logs de hoy:"
            docker logs dnsmasq-5354 2>/dev/null | grep "$(date +'%Y-%m-%d')" || echo "No hay logs para hoy."
            ;;
        b)
            echo -e "Logs completos:"
            docker logs dnsmasq-5354 2>/dev/null || echo "Error al consultar logs."
            ;;
        *)
            echo -e "Opción no válida."
            ;;
    esac
}

# Función para editar el archivo de configuración
editar_config() {
    echo -e "\nEDITAR CONFIGURACIÓN"
    echo "---------------------------------"
    # Editar el archivo de configuración (ruta a ajustar según corresponda)
    CONFIG_FILE="./dnsmasq.conf"
    if [[ -f "$CONFIG_FILE" ]]; then
        nano "$CONFIG_FILE"
    else
        echo -e "Archivo de configuración no encontrado en $CONFIG_FILE."
    fi
}

# Función para mostrar el menú principal
mostrar_menu() {
    echo -e "\n====== MENÚ PRINCIPAL ======"
    echo "1  Instalación del servicio"
    echo "   a) Con comandos"
    echo "   b) Con Ansible"
    echo "   c) Con Docker"
    echo "2  Eliminación del servicio"
    echo "3  Gestión del servicio (iniciar, detener, reiniciar, estado)"
    echo "4  Consultar logs"
    echo "5  Editar opciones de configuración"
    echo "6  Mostrar datos de red y estado del servicio"
    echo "0  Salir"
    echo "============================="
    read -p "Seleccione una opción: " opcionMenu
}

# Función para procesar parámetros desde la línea de comandos
procesar_parametros() {
    case "$1" in
        --install-cmd)
            echo -e "Instalación mediante comandos..."
            instalar_servicio
            ;;
        --install-ansible)
            echo -e "Instalación mediante Ansible..."
            ansible-playbook install_dnsmasq.yml || error_exit "Error al ejecutar el playbook de Ansible."
            ;;
        --install-docker)
            echo -e "Instalación mediante Docker..."
            docker pull diego57709/dnsmasq:latest || error_exit "Error al descargar la imagen."
            docker run -d --name dnsmasq-5354 -p 5354:5354/udp -p 5354:5354/tcp diego57709/dnsmasq:latest || error_exit "Error al iniciar el contenedor."
            ;;
        --status)
            estado_servicio
            ;;
        --logs)
            consultar_logs
            ;;
        --edit)
            editar_config
            ;;
        *)
            echo -e "Parámetro desconocido."
            exit 1
            ;;
    esac
}

# Si se pasan parámetros, procesarlos sin mostrar el menú interactivo
if [[ $# -gt 0 ]]; then
    procesar_parametros "$1"
    exit 0
fi

# Mostrar información inicial y menú interactivo
clear
mostrar_datos_red
estado_servicio

# Bucle principal que muestra el menú
while true; do
    mostrar_menu
    read -p "Seleccione una opción: " opcionMenu
    case "$opcionMenu" in
        1)
            echo -e "Seleccione método de instalación:"
            echo "   a) Con comandos"
            echo "   b) Con Ansible"
            echo "   c) Con Docker"
            read -p "Opción: " metodo
            case "$metodo" in
                a)
                    instalar_servicio
                    ;;
                b)
                    echo -e "Ejecutando playbook de Ansible..."
                    ansible-playbook install_dnsmasq.yml || echo -e "Error al ejecutar el playbook."
                    ;;
                c)
                    echo -e "Instalación mediante Docker..."
                    docker pull diego57709/dnsmasq:latest || error_exit "Error al descargar la imagen."
                    docker run -d --name dnsmasq-5354 -p 5354:5354/udp -p 5354:5354/tcp diego57709/dnsmasq:latest || error_exit "Error al iniciar el contenedor."
                    ;;
                *)
                    echo -e "Método no válido."
                    ;;
            esac
            ;;
        2)
            eliminar_servicio
            ;;
        3)
            gestionar_servicio
            ;;
        4)
            consultar_logs
            ;;
        5)
            editar_config
            ;;
        6)
            mostrar_datos_red
            estado_servicio
            ;;
        0)
            echo -e "Saliendo..."
            exit 0
            ;;
        *)
            echo -e "Opción no válida. Intente de nuevo."
            ;;
    esac
done
