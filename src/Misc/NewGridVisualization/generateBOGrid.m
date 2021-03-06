function [bogMap,xOff,yOff] = generateBOGrid(map)
            %create binary occupancy grid object and grid location objects
            
            %% prepare for drawing
            %nrOfCars = length([map.Vehicles.id]); %comment in if you know
            %the number of cars
            nrOfCars = 10;
            gSize = map.gridSize;
            %first we need map size
            %we can get it from waypoints with some space for better
            %display
            distances = map.connections.distances;
            w = map.waypoints;  %[x z y]
            w(:,3) = -1.*w(:,3);%transform to mobatsim coordinates
            xSize = max(w(:,1))-min(w(:,1))+100;
            xOff = min(w(:,1))-50;            
            ySize = max(w(:,3))-min(w(:,3))+100;
            yOff = min(w(:,3))-50;
            %calculate speedLimit [carID,edgeNR]
            maxEdgeSpeed = [map.connections.circle(:,end);map.connections.translation(:,end)];%TODO move to GridMap object and make it unique for every vehicle!
            speedLimit = zeros(nrOfCars,length(maxEdgeSpeed));
            for car = 1 : nrOfCars
                maxSpeed = map.Vehicles(car).dynamics.maxSpeed ;
                maxEdgeSpeed(maxEdgeSpeed>maxSpeed)= maxSpeed;
                speedLimit(car,:) = maxEdgeSpeed;
            end 
            
            bogMap = binaryOccupancyMap(xSize,ySize,gSize);
            %mark everything as blocked
            occ = ones(ySize*gSize,xSize*gSize);
            setOccupancy(bogMap,[0,0],occ);%lower left corner to set values
            
            %import map details
            trans = map.connections.translation; %[from to speed]
            circ = map.connections.circle; %[from to angle xzyCenter speed]
            circ(:,6) = -1.*circ(:,6);           
            
            %we iterate backwards in case we want to preallocate something
            
            %% bresenham algorithm
            for j = size(map.connections.all,1) :-1: (size(circ,1)+1) 
                t= j - size(circ,1);
                %j is nr for all, t only inside transitions
                dist = distances(j);
                %start node coordinates in grid
                p1 = bogMap.world2grid([w(trans(t,1),1)-xOff,w(trans(t,1),3)-yOff]);
                %end node coordinates in grid
                p2 = bogMap.world2grid([w(trans(t,2),1)-xOff,w(trans(t,2),3)-yOff]);
                %get difference
                deltaX = p2(1)-p1(1);
                delatY = p2(2)-p1(2);
                %get deistance and direction
                absDx = abs(deltaX);
                absDy = abs(delatY); % distance
                signDx = sign(deltaX);
                signDy = sign(delatY); % direction
                %determine which direction to go
                if absDx > absDy
                    % x is shorter
                    pdx = signDx;
                    pdy = 0;        %p is parallel
                    ddx = signDx;
                    ddy = signDy; % d is diagonal
                    deltaLongDirection  = absDy;
                    deltaShortDirection  = absDx;
                else
                    % y is shorter
                    pdx = 0;
                    pdy = signDy; % p is parallel
                    ddx = signDx;
                    ddy = signDy; % d is diagonal
                    deltaLongDirection  = absDx;
                    deltaShortDirection  = absDy;
                end
                %start at node 1
                x = p1(1);
                y = p1(2);
                setOccupancy(bogMap,[x,y],0,"grid");
                
                %create grid location================================= 
                startNodeNR = map.connections.all(j,1);
                endNodeNR = map.connections.all(j,2);
                curKey = append(num2str(x), ",", num2str(y));
                %if we dont have it -> create, else we import it
                if ~map.gridLocationMap.isKey(curKey)                
                    %if we dont have the gl in our map we need to add it
                    curGL = GridLocation([x,y],nrOfCars,startNodeNR,0);
                else
                    curGL = map.gridLocationMap(curKey);
                end
                pixelArray = [];
                %=====================================================                
                
                error = deltaShortDirection/2;
                
                %now set the pixel
                for i= 1:deltaShortDirection          
                    % for each pixel
                    % update error
                    error = error - deltaLongDirection;
                    if error < 0
                        error = error + deltaShortDirection; % error is never < 0
                        % go in long direction
                        x = x + ddx;
                        y = y + ddy; % diagonal
                    else
                        % go in short direction
                        x = x + pdx;
                        y = y + pdy; % parallel
                    end
                    setOccupancy(bogMap,[x,y],0,"grid");
                    %================={build grid}=======================
                    %treat the last one different
                    if i ~= deltaShortDirection                        
                        %create new GL
                        newKey = append(num2str(x), ",", num2str(y));                        
                        %create new key
                        if ~map.gridLocationMap.isKey(newKey)
                            newGL = GridLocation([x,y],nrOfCars,0,j);
                        else
                            newGL = map.gridLocationMap(newKey);
                        end
                        curGL = curGL.addTransSucc(newKey,startNodeNR);
                        newGL = newGL.addTransPred(curKey,endNodeNR);
                        %now we can add the old gl to the map                        
                        pixelArray = [pixelArray,curGL];
                        %remember for next round
                        
                        curGL = newGL;
                        curKey = newKey;
                    else
                        %if we dont have the gl in our map we need to add it
                        newKey = append(num2str(x), ",", num2str(y));
                        if ~map.gridLocationMap.isKey(newKey)
                            %create new GL
                            newGL = GridLocation([x,y],nrOfCars,map.connections.all(j,2),0);
                        else
                            %if it already exist, we just update succs and preds
                            newGL = map.gridLocationMap(newKey);
                        end
                        %assign grid relation
                        curGL = curGL.addTransSucc(newKey,startNodeNR);
                        newGL = newGL.addTransPred(curKey,endNodeNR);
                        pixelArray = [pixelArray,curGL,newGL];
                    end
                    %=====================================================
                end 
                %now assign properties
                dist = dist/size(pixelArray,2);
                for pix = pixelArray
                    p = pix.assignDistance(dist);
                    p.speedLimit = speedLimit(:,j);
                    %assign to map
                    map.gridLocationMap(append(num2str(p.coordinates(1)), ",", num2str(pix.coordinates(2))))=p;
                end
            end
                        
            %% draw a circle pixel by pixel
            for t = size(circ,1):-1:1
                
                dist = distances(t);
                pStart = bogMap.world2grid([w(circ(t,1),1)-xOff,w(circ(t,1),3)-yOff]); %start
                pGoal = bogMap.world2grid([w(circ(t,2),1)-xOff,w(circ(t,2),3)-yOff]); %goal
                pCenter = bogMap.world2grid([circ(t,4)-xOff,circ(t,6)-yOff]); %central point
                radius = round(norm( pGoal-pCenter  ),0);
                phiStart = angle(complex((pStart(1)-pCenter(1)) , (pStart(2)-pCenter(2))));
                phiGoal = angle(complex((pGoal(1)-pCenter(1)) , (pGoal(2)-pCenter(2))));
                direction = sign(circ(t,3));
                if phiStart <0
                    phiStart = phiStart + 2*3.1415;
                end
                if phiGoal <0
                    phiGoal = phiGoal + 2*3.1415;
                end
                offset = 0;
                %make turns through 0° possible
                if (direction == -1 && phiStart < phiGoal)
                    offset = 2*3.1415;
                    phiStart = phiStart + offset;
                end
                if (direction == 1 && phiStart > phiGoal)
                    offset = 2*3.1415;
                    phiGoal = phiGoal + offset;
                end
                
                %calculate the next pixel
                curPix = pStart;
                pixelArray = [];
                pixelArray = [pixelArray,append(num2str(curPix(1)), ",", num2str(curPix(2)))];
                curPhi = phiStart;
                while curPix(1) ~= pGoal(1) || curPix(2) ~= pGoal(2)
                    nextPix = [];   %the next pixel to draw in grid
                    nextPhi = 0;
                    deltaR = 200000;     %distance to the radius point with angle phi
                    %for every neighbour
                    for x = -1 : 1
                        for y = -1 : 1
                            if x ~= 0 || y ~= 0
                                %compare pixel for the closest one to the original
                                %point
                                %calculate the distance between the pixel and the
                                %reference and use the closest
                                neighbourPix = [curPix(1)+x,curPix(2)+y];%new pixel in grid
                                phi = angle(complex((neighbourPix(1)-pCenter(1)) , (neighbourPix(2)-pCenter(2))));%angle in world
                                if phi < 0
                                    phi = phi + 2*3.1415;
                                else
                                    phi = phi + offset;
                                end
                                %test, if the angle is relevant
                                if (direction == 1 && curPhi <= phi && phiGoal >= phi)|| (direction ==-1 && curPhi >= phi && phiGoal <= phi)
                                    referencePoint = [radius * cos(phi)+pCenter(1),radius*sin(phi)+pCenter(2)];%reference in world
                                    refDeltaR = norm(neighbourPix - referencePoint);
                                    if refDeltaR < deltaR
                                        deltaR = refDeltaR;
                                        nextPix = neighbourPix;
                                        nextPhi = phi;
                                    end
                                end
                            end
                        end
                    end                    
                    curPix = nextPix;
                    curPhi = nextPhi;
                    %now curPix is the next pixel to draw
                    pixelArray = [pixelArray, append(num2str(curPix(1)), ",", num2str(curPix(2)))];
                end
                %now draw pixel and assign to map
                startNodeNR = map.connections.all(t,1);
                endNodeNR = map.connections.all(t,2);
                curKey = pixelArray(1);
                dist = dist/size(pixelArray,2);
                %load or create gl for starting node
                if ~map.gridLocationMap.isKey(curKey)
                    curGL = GridLocation(pStart,nrOfCars,map.connections.all(t,1),0);
                else
                    curGL = map.gridLocationMap(curKey);
                end
                curGL = curGL.assignDistance(dist);%assign distance
                curGL.speedLimit = speedLimit(:,t);
                p = str2num(pixelArray(1));
                setOccupancy(bogMap,p,0,"grid");%draw
                
                for s = 2 : (length(pixelArray)-1)   %start connecting                 
                    newKey = pixelArray(s);
                    p = str2num(newKey);
                    setOccupancy(bogMap,p,0,"grid");
                    %create new GL
                    if ~map.gridLocationMap.isKey(newKey)
                        newGL = GridLocation(p,nrOfCars,0,t);
                    else
                        %load
                        newGL = map.gridLocationMap(newKey);
                    end
                    newGL = newGL.assignDistance(dist);
                    curGL.speedLimit = speedLimit(:,t);
                    %assign succ
                    curGL = curGL.addTransSucc(newKey,startNodeNR);
                    newGL = newGL.addTransPred(curKey,endNodeNR);
                    map.gridLocationMap(curKey)=curGL;
                    curGL = newGL;
                    oldKey = curKey;
                    curKey = newKey;                    
                end
                %if we dont have the gl in our map we need to add it
                newKey = pixelArray(end);
                if ~map.gridLocationMap.isKey(newKey)
                    %create new
                    p = str2num(newKey);
                    newGL = GridLocation(p,nrOfCars,map.connections.all(t,2),0);
                else
                    %load
                    newGL = map.gridLocationMap(newKey);
                end
                setOccupancy(bogMap,p,0,"grid");
                p = str2num(oldKey);
                setOccupancy(bogMap,p,0,"grid");
                %assign grid relation               
                newGL = newGL.assignDistance(dist);
                newGL.speedLimit = speedLimit(:,t);
                curGL = curGL.addTransSucc(newKey,startNodeNR);
                newGL = newGL.addTransPred(curKey,endNodeNR);
                map.gridLocationMap(curKey)=curGL;
                map.gridLocationMap(newKey)=newGL;
            end            
        end
