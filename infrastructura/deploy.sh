#!/bin/bash
echo "|== iniciando ==|"
# =================================
# SECCION 0: DEFINICION DE VARIABLES
# =================================
VPC_CIDR="10.0.0.0/16" 
VPC_NAME="lab1"
REGION="us-east-1" 
export AWS_DEFAULT_REGION=$REGION # Para asegurar la region


# Le prometo que a mi me encanta poner comentarios asi con lineas de '='
# =================================
# SECCION 1: CREACION VPC
# ================================
echo "Creando VPC con rango ${VPC_CIDR}"
# Creamos la VPC con el CIDR indicado previamente y guardamos su ID
export VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --query 'Vpc.VpcId' --output text)


echo ". . ." #Sin el echo no me dejaba comentar
  # Se hace validacion, para ver si se creo la vpc (NO TENIA IDEA QUE SE PODIAN GENERAR BLOQUES IF/ELSE ACA)
if [ -z "$VPC_ID" ] || [ "$VPC_ID" == "None" ]; then
    # Si VPC_ID esta vacio (osea no se creo) cierra todo
    echo "ERROR: No se pudo crear la VPC."
    exit 1

else
    # Si hay datos seguimos hacia delante
    echo "OK: VPC creada con ID: $VPC_ID"
fi

# asignacion de nombre
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME
echo "$VPC_ID ahora se llama $VPC_NAME"

# Permite asignacion de DNS,esto ayuda a identificar las maquinas de la VPC cambiando Ip por URL
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames



# ================================
# SECCION 2: CREAR SUBNETS
# ================================
echo "Iniciando creacion de subnet"
# Creamos una subnet en el mismo rango de la VPC, esta sera la subnet Publica 
export SUBNET_PUB=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --availability-zone ${REGION}a --query 'Subnet.SubnetId' --output text)
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

# Creamos otra subnet, igual ene l mismo rango de la VPC, esta sera la privada
export SUBNET_PRIV=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ${REGION}b --query 'Subnet.SubnetId' --output text)
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
# Creamos una internet gateway, usamos wait para esperar  la respuesta
export IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)

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
export RT_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
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
# SECCION 5: Security Group e Instancia
# # ================================

# Creamos el security group'y guardamos su id
export SG_ID=$(aws ec2 create-security-group --group-name sg-lab --description "lab SG" --vpc-id $VPC_ID --query 'GroupId' --output text)

if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    echo "ERROR: No se pudo crear el Security Group"
    exit 1

else
    echo "OK:Security Group creado con ID: $SG_ID"
fi
# Abrimos el puerto 80 al internet
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
# Dejamos el puerto 22 disponible unicamente para nuestra Ip personal
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 22 --cidr $(curl -s ifconfig.me)/32 

# En un principio la image-id estaba hardcodeada, la IA recomienda que se obtenga de forma dinamica, pq puede cambiar segun la region o el tiempo
# Personalmente no creo que cambie, pero soy paranoico, que pasa si del viernes al domingo amazon la cambia? Pues nada, hay que prevenir
export AMI_ID=$(aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
# otra captura de erroes mas

if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "None" ]; then
    echo "ERROR: No se pudo obtener la image-id"
    exit 1

else
    echo "OK: obtenemos imagen id: $AMI_ID"
fi
# Levantamos una instancia de t3.micro con Ubuntu server 26.04 (teoricamente deberia ser)
# Unico comando que hago saltar lineas pq estaba ilegible
export INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t3.micro \
    --subnet-id $SUBNET_PUB \
    --security-group-ids $SG_ID \
    --associate-public-ip-address \
    --key-name keybenja \
    --query 'Instances[0].InstanceId' --output text)

aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# SECCION: VERIFICAR!!!!!

# Obtenemos la IP publica de la maquina y esperamos respuesta!
export PUBLIC_IP=$(aws ec2 describe-instances --filters Name=subnet-id,Values=$SUBNET_PUB --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
ping -c 4 $PUBLIC_IP
