FROM eclipse-temurin:21-jre
WORKDIR /app
COPY app.jar app.jar
COPY db ./db
EXPOSE 8801
ENTRYPOINT ["java", "-jar", "app.jar"]
