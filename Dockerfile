FROM carlomt/geant4:11.4.2-bookworm AS build

WORKDIR /src
COPY CMakeLists.txt .
COPY src src
COPY test test
RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
 && cmake --build build --parallel \
 && test/smoke.sh build/g4fig

FROM carlomt/geant4:11.4.2-bookworm
LABEL io.g4fig.output-formats="svg,png,pdf"
RUN apt-get update \
 && apt-get install --yes --no-install-recommends librsvg2-bin \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/build/g4fig /usr/local/libexec/g4fig-render
COPY bin/container-entrypoint /usr/local/bin/g4fig
COPY --from=build /src/test /tmp/g4fig-test/test
RUN chmod +x /usr/local/bin/g4fig \
 && /tmp/g4fig-test/test/smoke.sh /usr/local/libexec/g4fig-render /usr/local/bin/g4fig \
 && rm -rf /tmp/g4fig-test
ENTRYPOINT ["g4fig"]
