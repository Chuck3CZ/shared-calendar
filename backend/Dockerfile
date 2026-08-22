FROM node:23-alpine

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev

COPY src ./src

ENV DB_PATH=/data/calendar.db
VOLUME ["/data"]

EXPOSE 3000
CMD ["node", "src/server.js"]
