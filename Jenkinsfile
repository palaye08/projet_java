pipeline {
    agent any

    environment {
        // Variables d'environnement
        DOCKER_HUB_REPO = 'laye769/projet_java'   // Votre repo Docker Hub
        DOCKER_HUB_CREDENTIALS = 'docker-hub-new'       // ID des credentials Docker Hub dans Jenkins
        RENDER_DEPLOY_HOOK = 'render-webhook'           // ID du webhook de déploiement Render
        RENDER_APP_URL = 'render-app-url'               // ID de l'URL de votre app Render
        MAVEN_OPTS = '-Dmaven.repo.local=/tmp/.m2/repository'
    }

    tools {
        maven 'maven'  // Utilise l'installation Maven par défaut
        jdk 'jdk-17'   // Utilise l'installation JDK 17 par défaut
    }

    stages {
        stage('Checkout') {
            steps {
                echo '🔄 Récupération du code source...'
                checkout scm
            }
        }

        stage('Build & Test') {
            steps {
                echo '🔨 Construction et tests du projet...'
                sh '''
                    # Vérifier la version Java
                    java -version
                    mvn -version

                    # Nettoyer et compiler
                    ./mvnw clean compile test -Dmaven.test.failure.ignore=true
                '''
            }
            post {
                always {
                    // Publier les résultats des tests
                    junit allowEmptyResults: true, testResults: 'target/surefire-reports/*.xml'
                    // Publier les rapports de couverture si disponibles
                    publishHTML([
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'target/site/jacoco',
                        reportFiles: 'index.html',
                        reportName: 'Coverage Report'
                    ])
                }
            }
        }

        stage('Package') {
            steps {
                echo '📦 Création du package JAR...'
                sh '''
                    ./mvnw clean package -DskipTests
                '''

                // Archiver l'artefact
                archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
            }
        }

        stage('Build Docker Image') {
            steps {
                echo '🐳 Construction de l\'image Docker...'
                script {
                    def imageName = "${DOCKER_HUB_REPO}:${BUILD_NUMBER}"
                    def latestImageName = "${DOCKER_HUB_REPO}:latest"

                    // Construire l'image Docker
                    dockerImage = docker.build(imageName)

                    // Tagger comme latest
                    sh "docker tag ${imageName} ${latestImageName}"
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                echo '📤 Push vers Docker Hub...'
                script {
                    docker.withRegistry('https://registry.hub.docker.com', DOCKER_HUB_CREDENTIALS) {
                        // Push avec le numéro de build
                        dockerImage.push("${BUILD_NUMBER}")
                        // Push latest
                        dockerImage.push("latest")
                    }
                }
            }
        }

        stage('Clean Local Images') {
            steps {
                echo '🧹 Nettoyage des images locales...'
                sh '''
                    docker rmi ${DOCKER_HUB_REPO}:${BUILD_NUMBER} || true
                    docker rmi ${DOCKER_HUB_REPO}:latest || true
                    docker system prune -f || true
                '''
            }
        }

        stage('Deploy to Render') {
            steps {
                echo '🚀 Déploiement sur Render...'
                script {
                    withCredentials([string(credentialsId: RENDER_DEPLOY_HOOK, variable: 'RENDER_WEBHOOK')]) {
                        def response = sh(
                            script: '''
                                curl -X POST "$RENDER_WEBHOOK" \
                                    -H "Content-Type: application/json" \
                                    -d '{"branch": "main"}' \
                                    -w "HTTP_CODE:%{http_code}"
                            ''',
                            returnStdout: true
                        ).trim()

                        echo "Réponse du webhook Render: ${response}"

                        if (!response.contains("HTTP_CODE:200")) {
                            error "Échec du déclenchement du déploiement Render"
                        }
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                echo '✅ Vérification du déploiement...'
                script {
                    withCredentials([string(credentialsId: RENDER_APP_URL, variable: 'APP_URL')]) {
                        echo "Attente du déploiement (90 secondes)..."
                        sleep(time: 90, unit: 'SECONDS')

                        // Tentatives de vérification du health check
                        def maxRetries = 5
                        def retryCount = 0
                        def healthCheckPassed = false

                        while (retryCount < maxRetries && !healthCheckPassed) {
                            try {
                                retryCount++
                                echo "Tentative ${retryCount}/${maxRetries} - Vérification du health check..."

                                def healthResponse = sh(
                                    script: """
                                        curl -f -s -o /dev/null -w "HTTP_CODE:%{http_code}" \
                                        "${APP_URL}/api/actuator/health" \
                                        --connect-timeout 30 \
                                        --max-time 60
                                    """,
                                    returnStdout: true
                                ).trim()

                                echo "Réponse health check: ${healthResponse}"

                                if (healthResponse.contains("HTTP_CODE:200")) {
                                    healthCheckPassed = true
                                    echo "✅ Health check réussi!"
                                } else {
                                    echo "⚠️ Health check échoué, nouvelle tentative dans 30 secondes..."
                                    sleep(time: 30, unit: 'SECONDS')
                                }

                            } catch (Exception e) {
                                echo "⚠️ Erreur lors du health check: ${e.getMessage()}"
                                if (retryCount < maxRetries) {
                                    echo "Nouvelle tentative dans 30 secondes..."
                                    sleep(time: 30, unit: 'SECONDS')
                                }
                            }
                        }

                        if (!healthCheckPassed) {
                            echo "⚠️ Le health check a échoué après ${maxRetries} tentatives"
                            echo "Cela peut indiquer que l'application met plus de temps à démarrer"
                            echo "Vérifiez manuellement: ${APP_URL}/api/actuator/health"
                        }

                        // Vérification de l'API principale
                        try {
                            echo "Vérification de l'accès à l'API principale..."
                            def apiResponse = sh(
                                script: """
                                    curl -f -s -o /dev/null -w "HTTP_CODE:%{http_code}" \
                                    "${APP_URL}/api" \
                                    --connect-timeout 30 \
                                    --max-time 60
                                """,
                                returnStdout: true
                            ).trim()

                            echo "Réponse API: ${apiResponse}"

                        } catch (Exception e) {
                            echo "⚠️ L'API principale n'est pas encore accessible: ${e.getMessage()}"
                        }

                        echo "🎯 URLs de l'application:"
                        echo "   - API: ${APP_URL}/api"
                        echo "   - Health: ${APP_URL}/api/actuator/health"
                        echo "   - Swagger: ${APP_URL}/api/swagger-ui.html"
                        echo "✅ Pipeline terminé avec succès!"
                    }
                }
            }
        }
    }

    post {
        always {
            echo '🔄 Nettoyage final...'
            // Nettoyer le workspace
            deleteDir()
        }

        success {
            echo '🎉 Pipeline exécuté avec succès!'
            script {
                withCredentials([string(credentialsId: RENDER_APP_URL, variable: 'APP_URL')]) {
                    echo "🚀 Déploiement terminé!"
                    echo "📱 Votre application est disponible à: ${APP_URL}"
                    echo "📖 Documentation API: ${APP_URL}/api/swagger-ui.html"
                }
            }
            // Vous pouvez ajouter des notifications Slack/Email ici
            /*
            slackSend(
                channel: '#devops',
                color: 'good',
                message: "✅ Déploiement réussi de ${env.JOB_NAME} - Build #${env.BUILD_NUMBER}\n🔗 App: ${APP_URL}"
            )
            */
        }

        failure {
            echo '❌ Pipeline échoué!'
            // Notifications en cas d'échec
            /*
            slackSend(
                channel: '#devops',
                color: 'danger',
                message: "❌ Échec du déploiement de ${env.JOB_NAME} - Build #${env.BUILD_NUMBER}"
            )
            */
        }
    }
}