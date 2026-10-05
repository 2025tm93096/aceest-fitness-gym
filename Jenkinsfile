pipeline {
    agent any

    environment {
        APP_IMAGE = 'aceest-fitness-app'
        TAG       = "${env.BUILD_NUMBER}"
    }

    stages {
        stage('SCM Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Static Lint Gate') {
            steps {
                sh '''
                    python3 -m venv venv || virtualenv venv
                    . venv/bin/activate
                    pip install --upgrade pip
                    pip install flake8
                    flake8 app/ tests/ --max-line-length=120
                '''
            }
        }

        stage('Build Docker Artifact') {
            steps {
                sh '''
                    docker build -t ${APP_IMAGE}:${TAG} .
                '''
            }
        }

        stage('Run In-Container Regression Tests') {
            steps {
                sh '''
                    docker run --rm ${APP_IMAGE}:${TAG} pytest tests/ -v
                '''
            }
        }
    }

    post {
        always {
            cleanWs()
        }
        success {
            echo "Jenkins Pipeline #${env.BUILD_NUMBER} passed successfully."
        }
        failure {
            echo "Jenkins Pipeline #${env.BUILD_NUMBER} failed."
        }
    }
}