#!/bin/bash
echo "|== iniciando ==|"
# =================================
# SECCION 0: DEFINICION DE VARIABLES
# =================================
VPC_CIDR="10.0.0.0/16" 
VPC_NAME="lab1"
REGION="us-east-1" 
export AWS_DEFAULT_REGION=$REGION # Para asegurar la region en cada comando
export PAGER=cat # Para que la terminal no se cuelgue con json de confirmacion
export AWS_PAGER=""

# Le prometo que a mi me encanta poner comentarios asi con lineas de '='
# =================================
# SECCION 1: CREACION VPC
# ================================
echo "Creando VPC con rango ${VPC_CIDR}"
# Creamos la VPC con el CIDR indicado previamente y guardamos su ID
export VPC_ID=$(aws ec2 create-vpc \
    --cidr-block $VPC_CIDR \
    --query 'Vpc.VpcId' --output text)


echo ". . ." #Sin el echo no me dejaba comentar
# Se hace validacion, para ver si se creo la vpc (NO TENIA IDEA QUE SE PODIAN GENERAR BLOQUES IF/ELSE ACA)
# Primero -z valida  si exite el dato, mientras None, valida si aws retorno "None", lo cual tambien es un error
if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
    # Si VPC_ID esta vacio (osea no se creo) cierra todo
    echo "ERROR: No se pudo crear la VPC."
    exit 1

else
    # Si hay datos seguimos hacia delante
    echo "OK: VPC creada con ID: $VPC_ID"
fi

# asignacion de nombre a la vpc
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME
echo "$VPC_ID ahora se llama $VPC_NAME"

# Permite asignacion de DNS,esto ayuda a identificar las maquinas de la VPC cambiando Ip por URL
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames



# ================================
# SECCION 2: CREAR SUBNET
# ================================
echo "Iniciando creacion de subnet"
# Creamos una subnet en el mismo rango de la VPC, esta sera la subnet Publica, avilitada en la region, hardcodeamos que sea 'us-east-1a'
export SUBNET_PUB=$(aws ec2 create-subnet\
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone ${REGION}a \
    --query 'Subnet.SubnetId' \
    --output text)
# captura de id a ver si hay error, si no veo mensajes conforma pasa el tiempo me da ansiedad
if [ -z "$SUBNET_PUB" ] || [ "$SUBNET_PUB" == "None" ]; then
    echo "ERROR: No se pudo crear la SUBNET Publica."
    exit 1

else
    echo "OK: SUBNET Publica creada con ID: $SUBNET_PUB"
fi

# Aprovecho que VPC_NAME es lab1 para asignar nombres de forma mas consistente
aws ec2 create-tags --resources $SUBNET_PUB --tags Key=Name,Value=${VPC_NAME}-Subnet-Pub
# Asigna Ip publicas automaticamente
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB --map-public-ip-on-launch

# Creamos otra subnet, igual ene l mismo rango de la VPC, esta sera la privada, esta esta harcodeada para estar en la misma region, pero otra zona
export SUBNET_PRIV=$(aws ec2 create-subnet --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone ${REGION}b \
    --query 'Subnet.SubnetId' \
    --output text)
# comprobacion
if [ -z "$SUBNET_PRIV" ] || [ "$SUBNET_PRIV" == "None" ]; then
    echo "ERROR: No se pudo crear la SUBNET Privada"
    exit 1

else
    echo "OK: SUBNET Privada creada con ID: $SUBNET_PRIV"
fi
# Lo del nombre de nuevo, pero ahora para la subnet privada
aws ec2 create-tags --resources $SUBNET_PRIV --tags Key=Name,Value=${VPC_NAME}-Subnet-Priv



# ================================
# SECCION 3: CREAR IGW
# ================================
echo "Iniciando creacion de Internet Gateway"
# Creamos una internet gateway, nada mas que comentar aca
export IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)

# Capturar de errores
if [ -z "$IGW_ID" ] || [ "$IGW_ID" == "None" ]; then
    echo "ERROR: No se pudo crear el Internet Gateway"
    exit 1

else
    echo "OK: Internet Gateway creado con ID: $IGW_ID"
fi

# Asignamos un nombre para el IGW, reciblo el de la vpc pero concateno '-IGW'
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value=${VPC_NAME}-IGW
# Conectamos el IGW con la VPC
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID



# ================================
# SECCION 4: Route Tables
# ================================
echo "Iniciando creacion de Route Tables"
# Le decimos a aws que la route table corresponde a la VPC que creamos en este archivo ya
export RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
# comprobacion de errores, bueno, de NO errores (se me acaban las frases)
if [ -z "$RT_ID" ] || [ "$RT_ID" == "None" ]; then
    echo "ERROR: No se pudo crear el Route Table"
    exit 1

else
    echo "OK: Route Table creado con ID: $RT_ID"
fi
# Me vuelvo a aprovechar de VPC_NAME para nombrar cosas, ahora el route-table
aws ec2 create-tags --resources $RT_ID --tags Key=Name,Value=${VPC_NAME}-Public-RT
# Damos acceso global (0.0.0.0/0) al internetgateway
aws ec2 create-route --route-table-id $RT_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
# Conectamos dicho acceso global a nuestra subnet publica
aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUBNET_PUB



# ================================
# SECCION 5: Security Group
# # ================================

# Creamos el security group y guardamos su id
# Le ponemos un nombre, como curiosidad al principio lo llame 'sg-lab', amazon da error automatico con eso
# El SG es asignado a la VPC ya creada
export SG_ID=$(aws ec2 create-security-group \
    --group-name lab1-security-group \
    --description "lab SG" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)
# comprobar
if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    echo "ERROR: No se pudo crear el Security Group"
    exit 1
else
    echo "OK:Security Group creado con ID: $SG_ID"
fi
# Abrimos el puerto HTTP (80) al internet
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0
# Dejamos el puerto ssh (22) disponible unicamente para nuestra Ip personal
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr $(curl -s ifconfig.me)/32 
# ================================
# SECCION 6: Instancia
# ================================


# En un principio la image-id estaba hardcodeada, la IA recomienda que se obtenga de forma dinamica, pq puede cambiar segun la region o el tiempo
# Personalmente no creo que cambie, pero soy paranoico, que pasa si del viernes al domingo amazon la cambia? Pues nada, hay que prevenir
# solicitamos la id de la imagen indicando la id correspondiente a cannonical, quienes son los dueños de ubuntu
# Solicitamos la ami_id de ubuntu-24 especificamente.
export AMI_ID=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)

# otra captura de erroes mas
if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
    echo "ERROR: No se pudo obtener la image-id"
    exit 1

else
    echo "OK: obtenemos imagen id: $AMI_ID"
fi

echo "Generando llave temporal"

rm -rf ./key_profe ./key_profe.pub
# Generamos una key privada para la session actual
ssh-keygen -t rsa -b 4096 -f ./key_profe -N "" -q
# Damos permisos de solo lectura a la llave
chmod 400 key_profe

# Eliminamos la llave activa (vital para ejecutar el .sh mas de una vez)
aws ec2 delete-key-pair --key-name "key-lab-profe" 2>/dev/null
# Cargamos la llave nueva a aws
aws ec2 import-key-pair --key-name "key-lab-profe" --public-key-material fileb://key_profe.pub

echo "OK: Llave 'key-lab-profe' lista en AWS."



# Levantamos una instancia de t3.micro con Ubuntu server 24.04 (teoricamente deberia ser)
# Aca creamos la instancia, le damos la imagen del SO que instalaremos, solicitamos que su capacidad de computo sea t3.micro
# La conectamos a la subnet publica, adeas de conectarla al grupo de seguridad configurado antes
# le digo que funciona con la key ya creada y registrada en linea
# Por ultimo comandos para ejecutar cosas DENTRO de la maquinita
echo "Generando Instancia"
export INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.micro \
    --subnet-id $SUBNET_PUB \
    --security-group-ids $SG_ID \
    --associate-public-ip-address \
    --key-name "key-lab-profe" \
    --user-data '#!/bin/bash
    # Actualizamos repositorios apt, la "y" hace que se responda si automaticamente (finalmente la considero util)
    apt-get update -y
    # instalamos apache
    apt-get install -y apache2' \
    --query 'Instances[0].InstanceId' --output text)

# Crear volumen en la misma AZ que la EC2
# size 8 significa 8 gigas, mientras gp3 significa que se usara un SSD general
# notar que el availability-zone es el mismo de la instancia para que se puedan conectar
# El disco es de tamaño 9 para diferenciarlo
echo "Generando volumen"
export VOL_ID=$(aws ec2 create-volume \
    --size 7 \
    --volume-type gp3 \
    --availability-zone ${REGION}a \
    --query 'VolumeId' --output text)

# Esperamos que el disco este listo
echo "Esperando volumen"
aws ec2 wait volume-available --volume-ids $VOL_ID

# Esperamos que la instancia este running
echo "Esperando instancia"
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Adjuntamos disco a la instancia
echo "Adjuntando instancia y disco"
aws ec2 attach-volume \
    --volume-id $VOL_ID \
    --instance-id $INSTANCE_ID\
    --device /dev/xvdf
echo "Disco adjuntado"
# Obtenemos la IP publica de la maquina y esperamos respuesta!
echo "Obteniendo IP publica"
export PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
ping -c 4 $PUBLIC_IP

echo "Ejecutando ssh para inicializar instancia"
# Iniciamos protocolo ssh usando la llave dentro del archivo
ssh -i key_profe ubuntu@$PUBLIC_IP << 'EOF'
    export PAGER=cat # Para que la terminal no se cuelgue con json de confirmacion
    export AWS_PAGER=""

    # en un principio hardcodee un timing para esperar a apache, pero era inseguro
    # La ia me recomendo este comando mejor, consulta al sistema si existe apache en ciclos de 3 segundos
    while ! systemctl is-active --quiet apache2; do sleep 3; done
    
    # vale hay que buscar el nombre que tiene el disco internamente
    # basicamente filtrmoas en la lista de discos y tomamos el que esta en la 'cabeza' jeje (son las 2am)
    DISK=$(lsblk -dnpo NAME,SIZE,TYPE | grep "disk" | grep "7G" | awk '{print $1}' | head -n 1)
    echo "Disco es: $DISK"


    # Formateamos el disco a formato ext4 
    sudo mkfs -t ext4 "$DISK"

    # creamos una carpeta y dejamos que sea el acceso al disco
    sudo mkdir -p /mnt/datos
    sudo mount "$DISK" /mnt/datos


    # creamos carpeta dentro del EBS
    sudo mkdir -p /mnt/datos/www-content


    # persistencia de discos, para que no se borren al reiniciar ni nada, aunque dudo que esto se reinicie, tipo solo servira una vez prendido
    echo "$DISK /mnt/datos ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
    echo "/mnt/datos/www-content /var/www/html none defaults,bind 0 0" | sudo tee -a /etc/fstab
    
    # montaje bind
    # basicamente hago que la carpeta donde guardamos la pagina en el ebs este conectada a la carpeta que lee apache
    sudo mount --bind /mnt/datos/www-content /var/www/html

    # reiniciamos apache
    sudo systemctl restart apache2
EOF


# ================================
# SECCION Pagina
# ================================

# Primero copiamos los archivos desde nuestra maquina a la instancia
echo "Copiando sitio web"
scp -i key_profe -r ../sitio-web/* ubuntu@$PUBLIC_IP:/home/ubuntu/

# Volvemos a hacer ssh a la maquina
echo "Iniciando ssh para mover archivos de instancia a EBS"
ssh -i key_profe ubuntu@$PUBLIC_IP  << 'EOF'
    export PAGER=cat # Para que la terminal no se cuelgue con json de confirmacion
    export AWS_PAGER=""
    # Copiamos los elementos que movimos de nuestra maquina a la carpeta en el EBS
    sudo mv /home/ubuntu/index.html /mnt/datos/www-content/
    sudo mv /home/ubuntu/styles.css /mnt/datos/www-content/
    sudo mv /home/ubuntu/imagenes /mnt/datos/www-content/


    # Nos aseguramos de cambiar los permisos
    sudo chown -R www-data:www-data /mnt/datos/www-content
    sudo chmod -R 755 /mnt/datos/www-content
    
    sudo systemctl restart apache2
    echo "pagina desplegar"
EOF



# ================================
# SECCION Verificaciones
# ================================
echo "Intancia EC2"
aws ec2 describe-instances --instance-ids $INSTANCE_ID

echo "Volumen EBS"
ssh -i key_profe ubuntu@$PUBLIC_IP << 'EOF'
    lsblk
    df -h
EOF

echo "Security group"
aws ec2 describe-security-groups --group-ids $SG_ID
