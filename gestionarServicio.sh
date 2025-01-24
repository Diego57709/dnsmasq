function gestionarServicio() {
    echo "MENÚ DE GESTIÓN DEL SERVICIO:"
    echo "1. Iniciar"
    echo "2. Detener"
    echo "3. Reiniciar"
    echo "4. Estado"
    read -p "Seleccione una acción para dnsmasq: " opcionGestion
    if [ $opcionGestion -eq 1 ]; then
        sudo systemctl start dnsmasq
        resultado=$?
        if [ $? ]; then
            echo "Servicio iniciado con exito"
        else
            echo "Error al iniciado el servicio, intentalo de nuevo"
        fi
    elif [ $opcionGestion -eq 2 ]; then
        sudo systemctl stop dnsmasq
        resultado=$?
        if [ $? ]; then
            echo "Servicio detenido con exito"
        else
            echo "Error al parar el servicio, intentalo de nuevo"
        fi
    elif [ $opcionGestion -eq 3 ]; then
        sudo systemctl restart dnsmasq
        resultado=$?
        if [ $? ]; then
            echo "Servicio reiniciado con exito"
        else
            echo "Error al reiniciar el servicio, intentalo de nuevo"
        fi
    elif [ $opcionGestion -eq 4 ]; then
        sudo systemctl --no-pager status dnsmasq
        resultado=$?
        if [ $? ]; then
            echo "Datos del servicio: "
        else
            echo "Error al conseguir el estado del servicio, intentalo de nuevo"
        fi
    fi
}
gestionarServicio
echo "Has elegido la opcion $opcionGestion"