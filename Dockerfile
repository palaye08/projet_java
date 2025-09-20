# Utiliser Amazon Corretto comme image de base pour le build
FROM amazoncorretto:17-alpine-jdk AS build

# Définir le répertoire de travail
WORKDIR /app

# Copier les fichiers Maven/Gradle wrapper et les fichiers de configuration
COPY mvnw .
COPY .mvn .mvn
COPY pom.xml .

# Rendre le wrapper Maven exécutable
RUN chmod +x ./mvnw

# Télécharger les dépendances (mise en cache des layers Docker)
RUN ./mvnw dependency:go-offline -B

# Copier le code source
COPY src src

# Construire l'application
RUN ./mvnw clean package -DskipTests

# Stage de production - image plus légère avec JRE seulement
FROM amazoncorretto:17-alpine

# Installer curl pour le health check
RUN apk add --no-cache curl

# Créer un utilisateur non-root pour la sécurité
RUN addgroup -g 1001 -S spring && adduser -u 1001 -S spring -G spring

# Définir le répertoire de travail
WORKDIR /app

# Copier le JAR depuis le stage de build
COPY --from=build /app/target/*.jar app.jar

# Changer la propriété du fichier à l'utilisateur spring
RUN chown spring:spring app.jar

# Changer vers l'utilisateur non-root
USER spring

# Exposer le port de l'application (Render utilise la variable PORT)
EXPOSE ${PORT:-10000}

# Définir les variables d'environnement pour optimiser la JVM
ENV JAVA_OPTS="-Xmx512m -Xms256m -Djava.security.egd=file:/dev/./urandom"
ENV SPRING_PROFILES_ACTIVE=docker

# Point d'entrée pour démarrer l'application avec le port dynamique
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -Dserver.port=${PORT:-10000} -jar app.jar"]

# Health check pour vérifier si l'application est en cours d'exécution
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:${PORT:-10000}/actuator/health || exit 1