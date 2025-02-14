#!/bin/bash
check_dnsmasq_docker() {
    # Buscar contenedor en ejecución basado en la imagen
    CONTAINER_RUNNING=$(docker ps -q --filter "ancestor=diego57709/dnsmasq")
    # Buscar si esta el contenedor
    CONTAINER_EXISTS=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
    # Verificar si existe la imagen
    IMAGE_EXISTS=$(docker images -q "diego57709/dnsmasq")

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
            docker pull diego57709/dnsmasq:latest
            docker run -d --name dnsmasq-5354 -p 5354:5354/udp -p 5354:5354/tcp diego57709/dnsmasq:latest
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

# Función para mostrar el menú principal
function mostrarMenu() {
    echo -e "\nMENÚ DE DNSMASQ EN DOCKER"
    echo "---------------------------------"
    echo "1  Gestionar el servicio"
    echo "2  Añadir registro DNS"
    echo "3  Borrar el servicio"
    echo "0  Salir"
}

# Función para gestionar el servicio (iniciar, detener, reiniciar, consultar estado)
function gestionarServicio() {
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
        # Si el contenedor está en ejecución coge su ID
        CONTAINER_ID=$(docker ps -q --filter "ancestor=diego57709/dnsmasq")
        case "$opcionGestion" in
            1) echo -e "El contenedor ya está en ejecución." ;;
            2) docker stop "$CONTAINER_ID" && echo -e "Contenedor detenido con éxito." || echo -e "Error al detener el contenedor." ;;
            3) docker restart "$CONTAINER_ID" && echo -e "Contenedor reiniciado con éxito." || echo -e "Error al reiniciar el contenedor." ;;
            4) docker ps --filter "id=$CONTAINER_ID" --format "ID: {{.ID}}, Estado: {{.Status}}" ;;
            *) echo -e "Opción no válida." ;;
        esac
    elif [[ $DOCKER_STATUS -eq 2 ]]; then
        # Si el contenedor existe pero está detenido
        CONTAINER_ID=$(docker ps -a -q --filter "ancestor=diego57709/dnsmasq")
        case "$opcionGestion" in
            1)
                docker start "$CONTAINER_ID" && echo -e "Contenedor iniciado con éxito." || echo -e "Error al iniciar el contenedor."
                check_dnsmasq_docker
                ;;
            2) echo -e "El contenedor ya está detenido." ;;
            3) docker restart "$CONTAINER_ID" && echo -e "Contenedor reiniciado con éxito." || echo -e "Error al reiniciar el contenedor." ;;
            4) docker ps --filter "id=$CONTAINER_ID" --format "ID: {{.ID}}, Estado: {{.Status}}" ;;
            *) echo -e "Opción no válida." ;;
        esac
    elif [[ $DOCKER_STATUS -eq 3 ]]; then
        # Si solo existe la imagen sin contenedor
        case "$opcionGestion" in
            1)
                docker run -d --name dnsmasq-5354 -p 5354:5354/udp -p 5354:5354/tcp diego57709/dnsmasq:latest \
                && echo -e "Contenedor creado e iniciado con éxito." \
                || echo -e "Error al crear/iniciar el contenedor."
                ;;
            *) echo -e "Opción no válida. Solo se permite iniciar el contenedor cuando no existe." ;;
        esac
    else
        echo -e "No se detecta dnsmasq en Docker."
    fi
}

# Función para eliminar el servicio
function eliminarServicio() {
    echo -e "\nELIMINAR DNSMASQ EN DOCKER"
    echo "---------------------------------"
    echo "1  Borrar solo el contenedor"
    echo "2  Borrar contenedor e imagen"
    echo "0  Volver al menú"
    read -p "Seleccione una opción: " opcionBorrar

    # Obtener el ID
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
                docker rmi diego57709/dnsmasq:latest
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

# Bucle que muestra el emnu
while true; do
    mostrarMenu
    read -p "Seleccione una opción: " opcionMenu
    case "$opcionMenu" in
        1) gestionarServicio ;;
        2) echo -e "Funcionalidad para añadir registro DNS (pendiente de implementación)." ;;
        3) eliminarServicio ;;
        0) echo -e "Saliendo..." && exit 0 ;;
        *) echo -e "Opción no válida. Intente de nuevo." ;;
    esac
done
