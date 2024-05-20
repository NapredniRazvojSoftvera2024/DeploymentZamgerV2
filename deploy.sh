#!/bin/bash

set -e
S3_BUCKET="zamger2bucket"
REPO_KEY_FE="https://zamger2bucket.s3.eu-north-1.amazonaws.com/repositories/Zamger2-WebApp.zip"
REPO_KEY_BE="https://zamger2bucket.s3.eu-north-1.amazonaws.com/repositories/Zamger2-Backend.zip"
DEPLOY_DIR="/home/ubuntu/DeploymentZamgerV2"
FRONTEND_DIR="/home/ubuntu/DeploymentZamgerV2/frontend"
BACKEND_DIR="/home/ubuntu/DeploymentZamgerV2/backend"
ENV_FILE_BACKEND="$DEPLOY_DIR/.env.backend"
FRONTEND_BRANCH="main"
BACKEND_BRANCH="main"
POSTGRES_USER="postgres"
POSTGRES_DB="newdb"

SUPER_ADMIN_FIRST_NAME="Admin"
SUPER_ADMIN_LAST_NAME="User"
SUPER_ADMIN_EMAIL="admin@etf.unsa.ba"
SUPER_ADMIN_PASSWORD='$2b$10$j/sUo5ceksdq8nH.Re1/2.iFjXlbMtB/KRPqLi31s74Eu0hFcoNz.'
SUPER_ADMIN_PHONE_NUMBER="1234567890"
SUPER_ADMIN_CREATED_AT="2020-05-14 04:00:00"
SUPER_ADMIN_ROLE_ID=1 

echo "Starting deployment of ZamgerV2"

if ! command -v curl &> /dev/null; then
    echo "Installing curl..."
    sudo apt-get install -y curl
fi

if ! command -v node &> /dev/null
then
    echo "Installing Node.js..."
    curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

if ! command -v npm &> /dev/null; then
    echo "Installing npm..."
    sudo apt-get install -y npm
fi

if ! command -v pm2 &> /dev/null
then
    echo "Installing PM2..."
    sudo npm install -g pm2
fi

if ! command -v psql &> /dev/null
then
    echo "Installing PostgreSQL..."
    sudo apt-get install -y postgresql postgresql-contrib
fi

if ! command -v nodemon &> /dev/null
then
    echo "Installing nodemon..."
    sudo npm install -g nodemon
fi

echo "Starting PostgreSQL service..."
sudo systemctl start postgresql
sudo systemctl enable postgresql

echo "Configuring PostgreSQL..."
sudo -u postgres psql -c "ALTER USER $POSTGRES_USER WITH SUPERUSER;"
sudo -u postgres psql -c "SELECT pg_terminate_backend(pg_stat_activity.pid) FROM pg_stat_activity WHERE pg_stat_activity.datname = '$POSTGRES_DB' AND pid <> pg_backend_pid();"
sudo -u postgres psql -c "DROP DATABASE IF EXISTS $POSTGRES_DB;"
sudo -u postgres psql -c "CREATE DATABASE $POSTGRES_DB OWNER $POSTGRES_USER;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;"

echo "monke"
if [ ! -d "$FRONTEND_DIR" ]; then
    cd $DEPLOY_DIR
    mkdir frontend
    echo "Downloading repository from S3..."
    curl -L $REPO_KEY_FE -o $DEPLOY_DIR/frontend/Zamger2-WebApp.zip
    unzip $DEPLOY_DIR/frontend/Zamger2-WebApp.zip -d $DEPLOY_DIR/frontend
echo "NO"
fi
cd $DEPLOY_DIR/frontend

echo "Installing frontend dependencies..."
sudo npm install

echo "Building the frontend application..."
sudo npm run build

if [ ! -d "$BACKEND_DIR" ]; then
    cd $DEPLOY_DIR
    mkdir backend
    curl -L $REPO_KEY_BE -o $DEPLOY_DIR/backend/Zamger2-Backend.zip
    unzip $DEPLOY_DIR/backend/Zamger2-Backend.zip -d $DEPLOY_DIR/backend

fi

cd $BACKEND_DIR

echo "Installing backend dependencies..."
sudo npm install

sudo chmod -R u+w $BACKEND_DIR

sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"

if [ ! -f "$BACKEND_DIR/.env" ]; then
    # Create .env file if it doesn't exist
    touch $BACKEND_DIR/.env
    sudo chmod 644 $BACKEND_DIR/.env 


echo "Creating .env file for backend..."
echo "DB_USER=postgres" >> $BACKEND_DIR/.env
echo "DB_PASSWORD=postgres" >> $BACKEND_DIR/.env
echo "POSTGRES_DB=newdb" >> $BACKEND_DIR/.env
echo "DB_HOST=localhost" >> $BACKEND_DIR/.env
echo "DB_PORT=5432" >> $BACKEND_DIR/.env
echo "NODE_ENV=development" >> $BACKEND_DIR/.env
echo "PORT=8080" >> $BACKEND_DIR/.env
echo "SECRET_KEY=travnikbreza" >> $BACKEND_DIR/.env
echo "TWO_FA_ISSUER=Zamger2" >> $BACKEND_DIR/.env
echo "TWO_FA_ACCOUNT=Zamger2" >> $BACKEND_DIR/.env
echo "CLIENT_ID=786324501372-d85k8h2o411v0q80gu1psof3q6ca224o.apps.googleusercontent.com" >> $BACKEND_DIR/.env
echo "S3_ACCESS_KEY=AKIAXYKJS4ADMZLPSX3U" >> $BACKEND_DIR/.env
echo "S3_SECRET_KEY=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" >> $BACKEND_DIR/.env
echo "S3_BUCKET_NAME=zamger2bucket" >> $BACKEND_DIR/.env
echo "S3_REGION=eu-north-1" >> $BACKEND_DIR/.env
fi

echo "Running Sequelize migrations..."
sudo npx sequelize-cli db:migrate

echo "Inserting super admin user into the database..."
sudo -u postgres psql -d $POSTGRES_DB -c "INSERT INTO users (first_name, last_name, email, password, phone_number, created_at, role_id) VALUES ('$SUPER_ADMIN_FIRST_NAME', '$SUPER_ADMIN_LAST_NAME', '$SUPER_ADMIN_EMAIL', '$SUPER_ADMIN_PASSWORD', '$SUPER_ADMIN_PHONE_NUMBER', '$SUPER_ADMIN_CREATED_AT', $SUPER_ADMIN_ROLE_ID);"

echo "Verifying super admin user insertion..."
SUPER_ADMIN_INSERTED=$(sudo -u postgres psql -d $POSTGRES_DB -t -c "SELECT COUNT(*) FROM users WHERE email = '$SUPER_ADMIN_EMAIL';")
if [ "$SUPER_ADMIN_INSERTED" -eq "1" ]; then
    echo "Super admin user inserted successfully."
else
    echo "Failed to insert super admin user."
    exit 1
fi

echo "Starting the backend application with PM2..."
sudo pm2 start npm --name "backend-app" -- run dev

sudo pm2 save

sudo pm2 startup systemd
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u $USER --hp $HOME

FRONTEND_RUNNING=$(pm2 list | grep frontend-app || true)
if [ -z "$FRONTEND_RUNNING" ]; then
    echo "Starting the frontend application..."
    cd $FRONTEND_DIR
    npm run dev &
else
    echo "Frontend application is already running."
fi

echo "Opening the frontend application in the default browser..."
xdg-open http://localhost:5173/

echo "Deployment completed successfully!"
