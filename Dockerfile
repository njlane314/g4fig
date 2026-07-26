FROM carlomt/geant4:11.4.2-bookworm AS build

WORKDIR /src
COPY CMakeLists.txt .
COPY src src
COPY test test
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build build --parallel \
 && test/smoke.sh build/g4fig

FROM carlomt/geant4:11.4.2-bookworm
COPY --from=build /src/build/g4fig /usr/local/bin/g4fig
ENTRYPOINT ["g4fig"]
