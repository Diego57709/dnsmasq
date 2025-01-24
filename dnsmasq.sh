#! /bin/bash
function mostrarMenu() {
    echo "---- MENÚ DE DNSMASQ (0-6) ---"
    echo "- 1.  Gestionar el servicio --"
    echo "- 2.  Añadir registro       --"
    echo "- 3.  Borrar el servicio    --"
    echo "- 0.  Salir                 --"
}
mostrarMenu
read -p "-     Opción: " opcion
echo "Has seleccionado la opción: $opcion"