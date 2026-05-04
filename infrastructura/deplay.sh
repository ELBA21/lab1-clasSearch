#!/bin/bash

echo "|== Iniciando ==|"
# =================================
# SECCION 0: DEFINICION DE VARIABLES
# =================================
VPC_CIDR="10.0.0.0/16" 
VPC_NAME="lab1"
REGION="us-east-1" 
export AWS_DEFAULT_REGION=$REGION # Para asegurar la region

# =================================
# SECCION 1: CREACION VPC
# ================================
echo "Creando VPC con rango ${VPC_CIDR}"
# Creamos la VPC con el CIDR indicado previamente y guardamos su ID
export VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --query 'Vpc.VpcId' --output text)


echo ". . ." #Sin el echo no me dejaba comentar
  # Se hace validacion, para ver si se creo (NO TENIA IDEA QUE SE PODIAN GENERAR BLOQUES IF/ELSE ACA)
if [ -z "$VPC_ID" ]; then
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
if [ -z "$SUBNET_PUB" ]; then
    echo "ERROR: No se pudo crear la SUBNET Publica."
    exit 1

else
    echo "OK: SUBNET Publica creada con ID: $SUBNET_PUB"
fi
# Asigna Ip publicas automaticamente
aws ec2 modify-subnet-attribute --subnet-id $SUBNET_PUB --map-public-ip-on-launch

# Creamos otra subnet, igual ene l mismo rango de la VPC, esta sera la privada
export SUBNET_PRIV=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --availability-zone ${REGION}b --query 'Subnet.SubnetId' --output text)
if [ -z "$SUBNET_PRIV" ]; then
    echo "ERROR: No se pudo crear la SUBNET Privada"
    exit 1

else
    echo "OK: SUBNET Privada creada con ID: $SUBNET_PRIV"
fi


# ================================
# SECCION 3: CREAR IGW
# ================================
echo "Iniciando creacion de Internet Gateway"
export IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)

if [ -z "$IGW_ID" ]; then
    echo "ERROR: No se pudo crear el Internet Gateway"
    exit 1

else
    echo "OK: Internet Gateway creado con ID: $IGW_ID"
fi

# Asignamos un nombre para el IGW, reciblo el de la vpc pero concateno '-IGW'
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value=${VPC_NAME}-IGW
# Conectamos el IGW con la VPC
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID

