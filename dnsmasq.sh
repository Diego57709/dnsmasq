#! /bin/bash
function mostrarMenu() {
    echo "MENÚ DE DNSMASQ (0-6)"
    echo "1.  Gestionar el servicio"
    echo "2.  Añadir registro"
    echo "3.  Borrar el servicio"
    echo "0.  Salir"
}
function gestionarServicio() {
    echo "MENÚ DE GESTIÓN DEL SERVICIO:"
    echo "1. Iniciar"
    echo "2. Detener"
    echo "3. Reiniciar"
    echo "4. Estado"
    read -p "Seleccione una acción para dnsmasq:" opcionGestion
}
mostrarMenu
read -p "Opción: " opcionMenu
echo "Has seleccionado la opción: $opcionMenu"

